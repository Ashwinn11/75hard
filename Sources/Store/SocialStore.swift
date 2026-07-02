import Foundation
import CloudKit
import Observation
import UIKit

// MARK: - Social layer (CloudKit public database)
//
// Friends connect via a short **invite code** — no usernames. Identity is your stable
// CloudKit user record ID (per Apple ID), so friendships and your profile survive reinstalls.
//
//  • `Invite`  — recordName = the CODE, field `owner` = your userID. A typed code resolves to a
//                userID with a single by-recordName fetch (no query/index needed).
//  • `Profile` — recordName = "u_<userID>", holds your display name + today's status. Friends read
//                it by direct fetch. Only its creator can edit it, so status can't be spoofed.
//  • `Follow`  — a directional edge, recordName "<fromID>__<toID>", fields from/to (userIDs). You
//                request by creating me→them; they accept by creating them→me. Both edges ⇒ friends.
//                Everyone only ever writes records they own.
//
// One-time CloudKit Dashboard setup (Development env, container iCloud.app.75her.com):
//   Record type `Follow` → add **Queryable** indexes on fields `from` and `to`.
//   (Invite and Profile are always fetched by exact recordName, so they need no index.)

/// One line in a friend's published daily checklist.
struct FriendHabit: Identifiable, Equatable, Codable {
    var title: String
    var done: Bool
    var time: String                // completion time e.g. "11:45am", "" when not done
    var id: String { title }
}

/// A friend's current challenge status, read from their public Profile record.
struct FriendStatus: Identifiable, Equatable {
    let id: String                  // userID
    let name: String
    let day: Int
    let done: Int
    let total: Int
    let challenge: String
    let updatedAt: Date?
    var photo: Data? = nil
    var bio: String = ""
    var habits: [FriendHabit] = []

    var displayName: String { name.isEmpty ? "Friend" : name }
}

/// A lightweight reference to a person (for pending / incoming request rows).
struct PersonRef: Identifiable, Equatable {
    let id: String                  // userID
    let name: String
    var bio: String = ""
    var photo: Data? = nil
    var displayName: String { name.isEmpty ? "Friend" : name }
}

/// A "people you may know" candidate. Match scoring ranks the list; the card shows only
/// photo / name / bio.
struct SuggestedPerson: Identifiable, Equatable {
    let id: String                  // userID
    let name: String
    let bio: String
    var photo: Data? = nil
    var displayName: String { name.isEmpty ? "Friend" : name }
}

enum SocialError: LocalizedError {
    case invalidCode
    case cantAddYourself
    case notReady
    case iCloudUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidCode:      return "No one found with that code. Double-check it and try again."
        case .cantAddYourself:  return "That's your own code."
        case .notReady:         return "Give it a second and try again."
        case .iCloudUnavailable:return "Sign in to iCloud in Settings to use Friends."
        }
    }
}

@MainActor
@Observable
final class SocialStore {
    static let shared = SocialStore()

    enum Phase: Equatable {
        case unknown                 // not bootstrapped yet
        case unavailable(String)     // no iCloud account, etc.
        case ready                   // good to go
    }

    private(set) var phase: Phase = .unknown
    private(set) var myCode: String?
    private(set) var friends: [FriendStatus] = []
    private(set) var incoming: [PersonRef] = []  // people who requested me (awaiting my accept)
    private(set) var outgoing: [PersonRef] = []  // people I requested (awaiting their accept)
    private(set) var suggested: [SuggestedPerson] = []  // live match-ranked people to add

    private let container = CKContainer(identifier: "iCloud.app.75her.com")
    private var db: CKDatabase { container.publicCloudDatabase }

    private var myID: String?
    private var myName = ""
    private var myChallenge = ""                  // my challenge title, for match-based suggestions
    private var justFollowed: Set<String> = []   // edges we just created; bridges CloudKit's read-after-write lag
    private var justRemoved: Set<String> = []    // edges we just deleted; bridges the same lag on removal
    private var myProfileRecord: CKRecord?
    private var lastPublishedKey = ""

    private enum RT { static let profile = "Profile"; static let follow = "Follow"; static let invite = "Invite" }
    private static let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")   // no 0/O/1/I/L

    private init() {}

    // MARK: Bootstrap

    /// Determine iCloud availability + our identity, ensure our invite code + profile exist,
    /// then load the friend graph. Cheap to call repeatedly.
    func bootstrap() async {
        if case .ready = phase { await refresh(); await syncPhoto(); return }
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                phase = .unavailable(SocialError.iCloudUnavailable.errorDescription!)
                return
            }
            myID = try await container.userRecordID().recordName
            await ensureInvite()
            await ensureProfile()
            phase = .ready
            await refresh()
            await syncPhoto()
        } catch {
            phase = .unavailable(SocialError.iCloudUnavailable.errorDescription!)
        }
    }

    // MARK: Invite code

    /// Make sure we have an invite code (an `Invite` record whose name is the code, pointing at us).
    private func ensureInvite() async {
        guard let myID else { return }
        if let saved = AppGroup.defaults.string(forKey: "socialCode") {
            myCode = saved
            return
        }
        for _ in 0..<6 {                                   // handle the astronomically unlikely collision
            let code = Self.randomCode()
            let id = CKRecord.ID(recordName: code)
            do {
                let existing = try await db.record(for: id)
                if (existing["owner"] as? String) == myID { adopt(code); return }
                continue                                   // taken by someone else — regenerate
            } catch let ck as CKError where ck.code == .unknownItem {
                let rec = CKRecord(recordType: RT.invite, recordID: id)
                rec["owner"] = myID
                do { _ = try await db.save(rec); adopt(code); return }
                catch let e as CKError where e.code == .serverRecordChanged { continue }   // lost a race
                catch { return }                           // network issue — try again next launch
            } catch {
                return
            }
        }
    }

    private func adopt(_ code: String) {
        myCode = code
        AppGroup.defaults.set(code, forKey: "socialCode")
    }

    private static func randomCode() -> String {
        var g = SystemRandomNumberGenerator()
        return String((0..<8).map { _ in codeAlphabet[Int.random(in: 0..<codeAlphabet.count, using: &g)] })
    }

    static func sanitizeCode(_ raw: String) -> String {
        let set = Set(codeAlphabet)
        return String(raw.uppercased().filter { set.contains($0) }.prefix(8))
    }

    /// Pretty display: "C62U 275A".
    static func format(_ code: String) -> String {
        let c = Array(code)
        guard c.count == 8 else { return code }
        return String(c[0..<4]) + " " + String(c[4..<8])
    }

    // MARK: Friend actions

    /// Resolve an invite code to the person it belongs to (name + bio) **without** adding them,
    /// so the UI can confirm "is this who you meant?" before sending a request.
    func lookup(_ raw: String) async throws -> PersonRef {
        guard case .ready = phase, let me = myID else { throw SocialError.notReady }
        let code = Self.sanitizeCode(raw)
        guard code.count >= 5 else { throw SocialError.invalidCode }

        let invite: CKRecord
        do { invite = try await db.record(for: CKRecord.ID(recordName: code)) }
        catch { throw SocialError.invalidCode }
        guard let targetID = invite["owner"] as? String else { throw SocialError.invalidCode }
        guard targetID != me else { throw SocialError.cantAddYourself }

        let profiles = await fetchProfiles([targetID])
        let p = profiles[targetID]
        return PersonRef(id: targetID,
                         name: (p?["name"] as? String) ?? "",
                         bio: (p?["bio"] as? String) ?? "",
                         photo: photoData(p))
    }

    /// Accept an incoming request (or send a new one). The local lists update the moment you tap —
    /// the CloudKit save and a background refresh reconcile afterwards.
    func accept(_ person: PersonRef) async throws {
        guard case .ready = phase else { throw SocialError.notReady }
        let isAccept = incoming.contains(where: { $0.id == person.id })

        if isAccept {
            // Accepting a request → they're a friend right away; live status fills in on refresh.
            incoming.removeAll { $0.id == person.id }
            if !friends.contains(where: { $0.id == person.id }) {
                friends.append(FriendStatus(id: person.id, name: person.name, day: 0, done: 0, total: 0,
                                            challenge: "", updatedAt: nil, photo: person.photo, bio: person.bio))
                friends.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            }
        } else if !outgoing.contains(where: { $0.id == person.id }) {
            // A fresh request → appears under Pending immediately.
            outgoing.append(person)
            outgoing.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }

        do { try await follow(person.id, kind: isAccept ? "accept" : "request") }
        catch { Task { await refresh() }; throw error }   // save failed — reconcile rolls the lists back
    }

    /// Record name for the directional edge from→to. CloudKit reserves record names beginning with
    /// "_", and a userRecordID can start with "_", so we prefix with "f_" to keep it valid.
    private func edgeID(_ from: String, _ to: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "f_\(from)__\(to)")
    }

    // Follow edges carry two timestamps that make removal a REAL disconnect (not an unfollow):
    //   updatedAt — when I last affirmed this person (request / accept / re-add)
    //   resetAt   — when I last removed them
    // An edge is only "active" if updatedAt > resetAt, and the other person's edge only counts
    // toward me if THEIR updatedAt postdates MY resetAt. So after a removal, both sides must go
    // through a fresh request → accept cycle — a stale old acceptance can never auto-reconnect.

    private func follow(_ targetID: String, kind: String) async throws {
        guard let me = myID else { throw SocialError.notReady }
        let id = edgeID(me, targetID)
        let edge: CKRecord
        do { edge = try await db.record(for: id) }                     // re-affirm my existing edge
        catch { edge = CKRecord(recordType: RT.follow, recordID: id) } // or start a fresh one
        edge["from"] = me
        edge["to"] = targetID
        edge["fromName"] = myName
        edge["kind"] = kind                 // "request" vs "accept" — an acceptance must never read as a sent request
        edge["updatedAt"] = Date()          // resetAt is intentionally preserved (they must re-accept)
        do { _ = try await db.save(edge) }
        catch let e as CKError where e.code == .serverRecordChanged { /* raced an identical save — fine */ }
        justFollowed.insert(targetID); justRemoved.remove(targetID)   // reflect immediately; index may lag
        Task { await refresh() }                                      // reconcile without blocking the tap
    }

    /// Remove someone — cancels an outgoing request or unfriends. Stamps resetAt on my edge, which
    /// voids their existing acceptance (and their app deletes its own edge on next refresh), so
    /// re-connecting requires a fresh request and accept from both sides.
    func remove(_ id: String) async {
        guard let me = myID else { return }
        // Optimistic: they leave the lists the moment you tap — and become suggestable again.
        if let f = friends.first(where: { $0.id == id }) {
            addToSuggested(id: id, name: f.name, bio: f.bio, photo: f.photo)
        } else if let p = (incoming + outgoing).first(where: { $0.id == id }) {
            addToSuggested(id: id, name: p.name, bio: p.bio, photo: p.photo)
        }
        friends.removeAll { $0.id == id }
        incoming.removeAll { $0.id == id }
        outgoing.removeAll { $0.id == id }
        justFollowed.remove(id); justRemoved.insert(id)
        do {
            // Fetch-or-create: a DECLINE stamps a tombstone even though I never had an edge.
            // The resetAt tells their app to drop its own edge, so my decline clears their
            // "request sent" row instead of leaving it hanging forever.
            let rid = edgeID(me, id)
            let rec: CKRecord
            do { rec = try await db.record(for: rid) }
            catch let ck as CKError where ck.code == .unknownItem {
                rec = CKRecord(recordType: RT.follow, recordID: rid)
            }
            rec["from"] = me
            rec["to"] = id
            rec["resetAt"] = Date()
            _ = try await db.save(rec)
        } catch {
            // Couldn't reach CloudKit — don't fake the removal (it would silently resurrect on
            // relaunch). Un-hide and let the reconcile show the truth.
            justRemoved.remove(id)
        }
        Task { await refresh() }
    }

    /// Unfriend an established friend — same reset semantics as remove.
    func unfriend(_ id: String) async { await remove(id) }

    /// Decline an incoming request — same reset semantics as remove: they move back into my
    /// suggestions instantly, and their pending row clears on their next refresh. If they later
    /// re-request (a NEW action after my decline), it shows up again — by design.
    func ignore(_ id: String) async { await remove(id) }

    /// Complete wipe: reset every edge I own (the tombstones make everyone else's app forget me),
    /// delete my Profile + Invite so no one can find me, clear all local social + onboarding
    /// state, and reset in-memory for a completely fresh start.
    func wipe() async {
        if let me = myID {
            // Reset (don't delete) my edges: the resetAt tombstone is what tells everyone else's
            // app to drop their own edge to me, so I truly disappear from their side too.
            for rec in await queryFollows(field: "from", equals: me) {
                rec["resetAt"] = Date()
                rec["fromName"] = ""
                _ = try? await db.save(rec)
            }
            _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: "u_\(me)"))
        }
        if let code = myCode {
            _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: code))
        }

        for k in ["socialCode", "socialBio", "socialIgnored", "socialPhotoUploadedV", "onbWant", "onbVibe", "onbHardest"] {
            AppGroup.defaults.removeObject(forKey: k)
        }
        UserDefaults.standard.removeObject(forKey: "profilePhotoV")
        try? FileManager.default.removeItem(at: ProfilePhoto.fileURL)

        myCode = nil; myProfileRecord = nil; myID = nil; myName = ""; myChallenge = ""; myBio = ""
        friends = []; incoming = []; outgoing = []; suggested = []
        justFollowed = []; justRemoved = []; lastPublishedKey = ""
        phase = .unknown
    }

    // MARK: Display name / bio

    /// Update my public display name (used e.g. during onboarding, before the first status publish).
    func setDisplayName(_ name: String) async {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != myName else { return }
        myName = n
        guard case .ready = phase else { return }
        do {
            let rec = try await myProfile()
            rec["name"] = n
            myProfileRecord = try await db.save(rec)
        } catch { }
    }

    private(set) var myBio: String = AppGroup.defaults.string(forKey: "socialBio") ?? ""

    // Onboarding quiz answers, persisted at onboarding finish — the match vocabulary for suggestions.
    private var myWant: String { AppGroup.defaults.string(forKey: "onbWant") ?? "" }
    private var myVibe: String { AppGroup.defaults.string(forKey: "onbVibe") ?? "" }
    private var myHardest: String { AppGroup.defaults.string(forKey: "onbHardest") ?? "" }

    /// Save my bio locally and to my public Profile (shown to others in suggestions).
    func setBio(_ raw: String) async {
        let bio = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        myBio = bio
        AppGroup.defaults.set(bio, forKey: "socialBio")
        guard case .ready = phase else { return }
        do {
            let rec = try await myProfile()
            rec["bio"] = bio
            myProfileRecord = try await db.save(rec)
        } catch { }
    }

    // MARK: Profile photo (published as a CloudKit asset)

    private var localPhotoVersion: Int { UserDefaults.standard.integer(forKey: "profilePhotoV") }
    private var uploadedPhotoVersion: Int {
        get { AppGroup.defaults.integer(forKey: "socialPhotoUploadedV") }
        set { AppGroup.defaults.set(newValue, forKey: "socialPhotoUploadedV") }
    }

    /// Upload my profile photo to my public Profile as a CKAsset, but only if it changed since the
    /// last upload (avoids re-sending the asset on every status publish).
    func syncPhoto() async {
        guard case .ready = phase else { return }
        let v = localPhotoVersion
        guard v != uploadedPhotoVersion, let asset = Self.currentPhotoAsset() else { return }
        do {
            let rec = try await myProfile()
            rec["photo"] = asset
            myProfileRecord = try await db.save(rec)
            uploadedPhotoVersion = v
        } catch { }
    }

    /// A small (≤256px) JPEG of the user's profile photo, as a CloudKit asset, or nil if none set.
    private static func currentPhotoAsset() -> CKAsset? {
        guard let raw = try? Data(contentsOf: ProfilePhoto.fileURL),
              let small = ImageProcessing.thumbnail(raw, maxPixel: 256),
              let data = ImageProcessing.jpeg(small) else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pfp_\(UUID().uuidString).jpg")
        guard (try? data.write(to: tmp)) != nil else { return nil }
        return CKAsset(fileURL: tmp)
    }

    /// Load the small avatar image bytes off a fetched Profile record's asset.
    private func photoData(_ rec: CKRecord?) -> Data? {
        guard let asset = rec?["photo"] as? CKAsset, let url = asset.fileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: Suggestions (match-based — challenge + onboarding answers)

    /// Refresh the live `suggested` list from the server, keeping locally re-suggested people
    /// (declined requests, removed friends) at the top so they're visible immediately.
    func loadSuggestions() async {
        let fresh = await fetchRankedSuggestions()
        let keep = suggested.filter { s in
            !fresh.contains { $0.id == s.id } &&
            !friends.contains { $0.id == s.id } &&
            !incoming.contains { $0.id == s.id }
        }
        suggested = keep + fresh
    }

    /// Put someone back into the suggestions list (front), e.g. after a decline or unfriend.
    private func addToSuggested(id: String, name: String, bio: String, photo: Data?) {
        guard !suggested.contains(where: { $0.id == id }) else { return }
        suggested.insert(SuggestedPerson(id: id, name: name, bio: bio, photo: photo), at: 0)
    }

    /// People to add, ranked by how well they match me: same challenge first, then shared quiz
    /// answers (want / vibe / hardest), then most recently active. Draws from ALL public profiles,
    /// so it's never empty as long as other users exist — even with zero friends.
    private func fetchRankedSuggestions() async -> [SuggestedPerson] {
        guard case .ready = phase, let me = myID else { return [] }

        var exclude = Set(friends.map(\.id)); exclude.insert(me)
        exclude.formUnion(incoming.map(\.id)); exclude.formUnion(outgoing.map(\.id))

        let recs = await queryRecentProfiles(limit: 120)
        let ranked = recs.compactMap { rec -> (person: SuggestedPerson, score: Int, at: Date)? in
            guard let id = ownerID(of: rec), !exclude.contains(id) else { return nil }

            var score = 0
            if !myChallenge.isEmpty, (rec["challenge"] as? String) == myChallenge { score += 4 }
            for (mine, key) in [(myWant, "want"), (myVibe, "vibe"), (myHardest, "hardest")] {
                if !mine.isEmpty, (rec[key] as? String) == mine { score += 2 }
            }

            let person = SuggestedPerson(
                id: id,
                name: (rec["name"] as? String) ?? "",
                bio: (rec["bio"] as? String) ?? "",
                photo: photoData(rec))
            return (person, score, (rec["updatedAt"] as? Date) ?? .distantPast)
        }

        return ranked
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.at > $1.at }
            .prefix(40)
            .map(\.person)
    }

    /// The most recently active public profiles (everyone who's published a status).
    private func queryRecentProfiles(limit: Int) async -> [CKRecord] {
        let q = CKQuery(recordType: RT.profile,
                        predicate: NSPredicate(format: "updatedAt > %@", Date(timeIntervalSince1970: 0) as NSDate))
        q.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        do {
            let (matches, _) = try await db.records(matching: q, resultsLimit: limit)
            return matches.compactMap { try? $0.1.get() }
        } catch {
            return []   // Profile.updatedAt not queryable yet, or no profiles — treat as empty.
        }
    }

    private func ownerID(of rec: CKRecord) -> String? {
        if let o = rec["owner"] as? String, !o.isEmpty { return o }
        let n = rec.recordID.recordName
        return n.hasPrefix("u_") ? String(n.dropFirst(2)) : nil
    }

    // MARK: Refresh graph

    private var refreshing = false

    func refresh() async {
        guard case .ready = phase, let me = myID else { return }
        guard !refreshing else { return }   // coalesce: 3 tabs bootstrapping at once = 1 refresh
        refreshing = true; defer { refreshing = false }

        let incomingRecs = await queryFollows(field: "to", equals: me)      // edges → me
        let outgoingRecs = await queryFollows(field: "from", equals: me)    // edges from me

        func ts(_ rec: CKRecord?, _ key: String) -> TimeInterval {
            (rec?[key] as? Date)?.timeIntervalSince1970 ?? 0
        }
        func isActive(_ rec: CKRecord) -> Bool { ts(rec, "updatedAt") > ts(rec, "resetAt") }

        var mine: [String: CKRecord] = [:]      // my edge per target (including reset ones)
        for rec in outgoingRecs { if let to = rec["to"] as? String { mine[to] = rec } }
        var theirs: [String: CKRecord] = [:]    // their edge per person
        for rec in incomingRecs { if let from = rec["from"] as? String { theirs[from] = rec } }

        // Retire the lag-bridges once the server confirms the action they were covering —
        // an immortal bridge lies: a stale justFollowed resurrects a deleted edge as "request
        // sent"; a stale justRemoved would hide a future incoming request forever.
        justFollowed = justFollowed.filter { id in
            guard let m = mine[id] else { return true }   // not indexed yet — keep bridging
            return !isActive(m)                            // stale pre-affirm copy — keep bridging
        }
        justRemoved = justRemoved.filter { id in
            guard let m = mine[id] else { return false }   // gone — removal confirmed
            return isActive(m)                             // still active server-side — keep hiding
        }

        // Auto-clean: someone removed me after I last AFFIRMED them → my affirmation is void.
        // Delete my own edge so the disconnect is complete on both sides. Only an ACTIVE edge
        // qualifies — an inactive one is my reset-tombstone, and deleting it would erase the
        // memory that voids their older request (declined requests would resurrect forever).
        for (id, their) in theirs {
            if let m = mine[id], isActive(m), ts(their, "resetAt") > ts(m, "updatedAt") {
                _ = try? await db.deleteRecord(withID: m.recordID)
                mine.removeValue(forKey: id)
            }
        }

        // Auto-clean: a dangling ACCEPTANCE. My accept-edge is only meaningful while the request
        // it answered is still standing — if their side is gone or predates my reset, the
        // friendship was revoked, and an acceptance must never show up as "request sent".
        for (id, m) in mine {
            guard isActive(m), (m["kind"] as? String) == "accept", !justFollowed.contains(id) else { continue }
            let theirValid = theirs[id].map { isActive($0) && ts($0, "updatedAt") > ts(m, "resetAt") } ?? false
            if !theirValid {
                _ = try? await db.deleteRecord(withID: m.recordID)
                mine.removeValue(forKey: id)
            }
        }

        let outgoingTo = Set(mine.filter { isActive($0.value) }.keys)
            .union(justFollowed).subtracting(justRemoved)
        // Their edge counts only if it's active AND newer than my last removal of them.
        let incomingFrom = Set(theirs.filter { id, rec in
            isActive(rec) && ts(rec, "updatedAt") > ts(mine[id], "resetAt")
        }.keys).subtracting(justRemoved)

        // Friends additionally require MY affirmation to postdate THEIR last removal of me.
        let friendIds = incomingFrom.intersection(outgoingTo).filter { id in
            guard let m = mine[id] else { return true }   // freshly followed; record not queryable yet
            return ts(m, "updatedAt") > ts(theirs[id], "resetAt")
        }
        let incomingIds = incomingFrom.subtracting(outgoingTo)
        let outgoingIds = outgoingTo.subtracting(incomingFrom)

        let profiles = await fetchProfiles(friendIds.union(incomingIds).union(outgoingIds))

        // Fallback names from the edges, in case a profile hasn't been published yet.
        let edgeNames = Dictionary(incomingRecs.compactMap { rec -> (String, String)? in
            guard let f = rec["from"] as? String, let n = rec["fromName"] as? String, !n.isEmpty else { return nil }
            return (f, n)
        }, uniquingKeysWith: { a, _ in a })

        func name(_ id: String) -> String { (profiles[id]?["name"] as? String) ?? edgeNames[id] ?? "" }

        friends = friendIds.map { status(for: $0, profiles: profiles) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        incoming = incomingIds.map { PersonRef(id: $0, name: name($0), photo: photoData(profiles[$0])) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        outgoing = outgoingIds.map { PersonRef(id: $0, name: name($0), photo: photoData(profiles[$0])) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func status(for id: String, profiles: [String: CKRecord]) -> FriendStatus {
        let r = profiles[id]
        return FriendStatus(
            id: id,
            name: (r?["name"] as? String) ?? "",
            day: (r?["day"] as? Int) ?? 0,
            done: (r?["done"] as? Int) ?? 0,
            total: (r?["total"] as? Int) ?? 0,
            challenge: (r?["challenge"] as? String) ?? "",
            updatedAt: r?["updatedAt"] as? Date,
            photo: photoData(r),
            bio: (r?["bio"] as? String) ?? "",
            habits: decodeHabits(r?["habits"] as? String))
    }

    private func decodeHabits(_ json: String?) -> [FriendHabit] {
        guard let data = json?.data(using: .utf8),
              let list = try? JSONDecoder().decode([FriendHabit].self, from: data) else { return [] }
        return list
    }

    // MARK: Publish my status

    /// Push my current day/completion to my Profile so friends can see it. Throttled.
    func publish(day: Int, done: Int, total: Int, challenge: String, name: String, habitsJSON: String) async {
        guard case .ready = phase else { return }
        if !name.isEmpty { myName = name }
        if !challenge.isEmpty { myChallenge = challenge }
        let key = "\(day)|\(done)|\(total)|\(challenge)|\(name)|\(habitsJSON)|\(myWant)|\(myVibe)|\(myHardest)"
        guard key != lastPublishedKey else { return }
        do {
            let rec = try await myProfile()
            if !name.isEmpty { rec["name"] = name }
            rec["bio"] = myBio
            rec["day"] = day
            rec["done"] = done
            rec["total"] = total
            rec["challenge"] = challenge
            rec["habits"] = habitsJSON
            rec["want"] = myWant
            rec["vibe"] = myVibe
            rec["hardest"] = myHardest
            rec["updatedAt"] = Date()
            myProfileRecord = try await db.save(rec)
            lastPublishedKey = key
        } catch {
            // Non-fatal; we'll try again on the next change.
        }
    }

    /// Ensure a Profile record exists so friends can resolve our name even before first publish.
    private func ensureProfile() async {
        do { _ = try await myProfile() } catch { }
    }

    private func myProfile() async throws -> CKRecord {
        if let r = myProfileRecord { return r }
        guard let me = myID else { throw SocialError.notReady }
        let id = CKRecord.ID(recordName: "u_\(me)")
        do {
            let r = try await db.record(for: id)
            myProfileRecord = r
            return r
        } catch let ck as CKError where ck.code == .unknownItem {
            let r = CKRecord(recordType: RT.profile, recordID: id)
            r["owner"] = me
            if !myName.isEmpty { r["name"] = myName }
            if !myBio.isEmpty { r["bio"] = myBio }
            myProfileRecord = try await db.save(r)
            return myProfileRecord!
        }
    }

    // MARK: CloudKit helpers

    private func queryFollows(field: String, equals value: String) async -> [CKRecord] {
        let q = CKQuery(recordType: RT.follow, predicate: NSPredicate(format: "%K == %@", field, value))
        do {
            let (matches, _) = try await db.records(matching: q, resultsLimit: 300)
            return matches.compactMap { try? $0.1.get() }
        } catch {
            // Record type not created yet (no follows exist) or missing index — treat as empty.
            return []
        }
    }

    private func fetchProfiles(_ ids: Set<String>) async -> [String: CKRecord] {
        guard !ids.isEmpty else { return [:] }
        let recordIDs = ids.map { CKRecord.ID(recordName: "u_\($0)") }
        do {
            let results = try await db.records(for: recordIDs)
            var out: [String: CKRecord] = [:]
            for (id, res) in results {
                if let rec = try? res.get() {
                    out[String(id.recordName.dropFirst(2))] = rec   // strip "u_"
                }
            }
            return out
        } catch {
            return [:]
        }
    }
}

extension SocialStore {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"; f.pmSymbol = "pm"
        return f
    }()

    /// Publish today's real status for a challenge (day / done / total / title / name + checklist).
    func publishStatus(for challenge: Challenge) async {
        let today = Date()
        let habits = challenge.habitsOrdered
        let items: [FriendHabit] = habits.map { h in
            let c = h.completion(on: today)
            return FriendHabit(title: h.title,
                               done: c != nil,
                               time: c.map { Self.timeFormatter.string(from: $0.loggedAt) } ?? "")
        }
        let done = items.filter(\.done).count
        let json = (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        await publish(day: challenge.currentDay, done: done, total: habits.count,
                      challenge: challenge.track.title, name: challenge.ownerName, habitsJSON: json)
    }
}
