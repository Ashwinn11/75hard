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
    var fraction: Double { total <= 0 ? 0 : min(1, Double(done) / Double(total)) }
    var isComplete: Bool { total > 0 && done >= total }
}

/// A lightweight reference to a person (for pending / incoming request rows).
struct PersonRef: Identifiable, Equatable {
    let id: String                  // userID
    let name: String
    var bio: String = ""
    var photo: Data? = nil
    var displayName: String { name.isEmpty ? "Friend" : name }
}

/// A "people you may know" candidate — a friend-of-a-friend, with a bio preview.
struct SuggestedPerson: Identifiable, Equatable {
    let id: String                  // userID
    let name: String
    let bio: String
    var photo: Data? = nil
    var sameChallenge: Bool = false // on the same challenge as me
    var challengeTitle: String = "" // their challenge, shown as a tag
    var sharedTags: [String] = []   // matching quiz answers (want / vibe / hardest)
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
    private(set) var isBusy = false

    private let container = CKContainer(identifier: "iCloud.app.75her.com")
    private var db: CKDatabase { container.publicCloudDatabase }

    private var myID: String?
    private var myName = ""
    private var myChallenge = ""                  // my challenge title, for match-based suggestions
    private var justFollowed: Set<String> = []   // edges we just created; bridges CloudKit's read-after-write lag
    private var justRemoved: Set<String> = []    // edges we just deleted; bridges the same lag on removal
    private var myProfileRecord: CKRecord?
    private var lastPublishedKey = ""
    private var ignoredIncoming: Set<String> {
        get { Set(AppGroup.defaults.stringArray(forKey: "socialIgnored") ?? []) }
        set { AppGroup.defaults.set(Array(newValue), forKey: "socialIgnored") }
    }

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

    /// Add a friend by their invite code: resolve code → their userID → create our edge me→them.
    func addByCode(_ raw: String) async throws {
        guard case .ready = phase, let me = myID else { throw SocialError.notReady }
        let code = Self.sanitizeCode(raw)
        guard code.count >= 5 else { throw SocialError.invalidCode }
        isBusy = true; defer { isBusy = false }

        let invite: CKRecord
        do { invite = try await db.record(for: CKRecord.ID(recordName: code)) }
        catch { throw SocialError.invalidCode }
        guard let targetID = invite["owner"] as? String else { throw SocialError.invalidCode }
        guard targetID != me else { throw SocialError.cantAddYourself }

        if ignoredIncoming.contains(targetID) { ignoredIncoming.remove(targetID) }
        try await follow(targetID)
    }

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

    /// Accept an incoming request (or re-affirm a friendship) by creating our edge me→them.
    func accept(_ person: PersonRef) async throws {
        guard case .ready = phase else { throw SocialError.notReady }
        isBusy = true; defer { isBusy = false }
        if ignoredIncoming.contains(person.id) { ignoredIncoming.remove(person.id) }
        try await follow(person.id)
    }

    /// Record name for the directional edge from→to. CloudKit reserves record names beginning with
    /// "_", and a userRecordID can start with "_", so we prefix with "f_" to keep it valid.
    private func edgeID(_ from: String, _ to: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "f_\(from)__\(to)")
    }

    private func follow(_ targetID: String) async throws {
        guard let me = myID else { throw SocialError.notReady }
        let edge = CKRecord(recordType: RT.follow, recordID: edgeID(me, targetID))
        edge["from"] = me
        edge["to"] = targetID
        edge["fromName"] = myName
        edge["updatedAt"] = Date()
        do { _ = try await db.save(edge) }
        catch let e as CKError where e.code == .serverRecordChanged { /* already exists — fine */ }
        justFollowed.insert(targetID); justRemoved.remove(targetID)   // reflect immediately; index may lag
        ignoredIncoming.remove(targetID)                              // re-adding un-ignores them
        await refresh()
    }

    /// Remove our edge me→them. Cancels an outgoing request.
    func remove(_ id: String) async {
        guard let me = myID else { return }
        isBusy = true; defer { isBusy = false }
        _ = try? await db.deleteRecord(withID: edgeID(me, id))
        justFollowed.remove(id); justRemoved.insert(id)
        await refresh()
    }

    /// Unfriend an established friend: delete my edge to them AND ignore their edge to me, so they
    /// don't bounce back as an incoming request (I can't delete the edge they own).
    func unfriend(_ id: String) async {
        guard let me = myID else { return }
        isBusy = true; defer { isBusy = false }
        _ = try? await db.deleteRecord(withID: edgeID(me, id))
        justFollowed.remove(id); justRemoved.insert(id)
        var set = ignoredIncoming; set.insert(id); ignoredIncoming = set
        await refresh()
    }

    /// Locally dismiss an incoming request without accepting (we can't delete their edge).
    func ignore(_ id: String) async {
        var set = ignoredIncoming; set.insert(id); ignoredIncoming = set
        await refresh()
    }

    /// Complete wipe: delete every record I own (Profile, Invite, all my outgoing Follow edges) so
    /// no one can find me, clear all local social + onboarding state, and reset in-memory. Former
    /// followers' edges to me (which I can't delete) are added to the ignore set so they don't
    /// resurface as requests when I start over.
    func wipe() async {
        isBusy = true; defer { isBusy = false }
        let toBlock = Set(friends.map(\.id)).union(incoming.map(\.id)).union(outgoing.map(\.id))

        if let me = myID {
            for rec in await queryFollows(field: "from", equals: me) {
                _ = try? await db.deleteRecord(withID: rec.recordID)
            }
            _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: "u_\(me)"))
        }
        if let code = myCode {
            _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: code))
        }

        for k in ["socialCode", "socialBio", "socialPhotoUploadedV", "onbWant", "onbVibe", "onbHardest"] {
            AppGroup.defaults.removeObject(forKey: k)
        }
        UserDefaults.standard.removeObject(forKey: "profilePhotoV")
        try? FileManager.default.removeItem(at: ProfilePhoto.fileURL)
        ignoredIncoming = toBlock

        myCode = nil; myProfileRecord = nil; myID = nil; myName = ""; myChallenge = ""
        friends = []; incoming = []; outgoing = []; justFollowed = []; justRemoved = []; lastPublishedKey = ""
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

    var myBio: String { AppGroup.defaults.string(forKey: "socialBio") ?? "" }

    // Onboarding quiz answers, persisted at onboarding finish — the match vocabulary for suggestions.
    private var myWant: String { AppGroup.defaults.string(forKey: "onbWant") ?? "" }
    private var myVibe: String { AppGroup.defaults.string(forKey: "onbVibe") ?? "" }
    private var myHardest: String { AppGroup.defaults.string(forKey: "onbHardest") ?? "" }

    /// Save my bio locally and to my public Profile (shown to others in suggestions).
    func setBio(_ raw: String) async {
        let bio = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
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
        let src = ProfilePhoto.fileURL
        guard FileManager.default.fileExists(atPath: src.path),
              let img = UIImage(contentsOfFile: src.path) else { return nil }
        let side: CGFloat = 256
        let scale = min(1, side / max(img.size.width, img.size.height))
        let target = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let small = UIGraphicsImageRenderer(size: target).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = small.jpegData(compressionQuality: 0.8) else { return nil }
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

    /// People to add, ranked by how well they match me: same challenge first, then shared quiz
    /// answers (want / vibe / hardest), then most recently active. Draws from ALL public profiles,
    /// so it's never empty as long as other users exist — even with zero friends.
    func suggestions() async -> [SuggestedPerson] {
        guard case .ready = phase, let me = myID else { return [] }

        // Note: ignored people are intentionally NOT excluded — a friend you removed should be
        // re-addable from suggestions (removing them added them to the ignore set so they don't
        // reappear as a *request*, but they can still be re-added here).
        var exclude = Set(friends.map(\.id)); exclude.insert(me)
        exclude.formUnion(incoming.map(\.id)); exclude.formUnion(outgoing.map(\.id))

        let recs = await queryRecentProfiles(limit: 120)
        let ranked = recs.compactMap { rec -> (person: SuggestedPerson, score: Int, at: Date)? in
            guard let id = ownerID(of: rec), !exclude.contains(id) else { return nil }

            var score = 0
            var shared: [String] = []
            let theirChallenge = (rec["challenge"] as? String) ?? ""
            let sameChallenge = !myChallenge.isEmpty && theirChallenge == myChallenge
            if sameChallenge { score += 4 }
            for (mine, key) in [(myWant, "want"), (myVibe, "vibe"), (myHardest, "hardest")] {
                if !mine.isEmpty, (rec[key] as? String) == mine { score += 2; shared.append(mine) }
            }

            let person = SuggestedPerson(
                id: id,
                name: (rec["name"] as? String) ?? "",
                bio: (rec["bio"] as? String) ?? "",
                photo: photoData(rec),
                sameChallenge: sameChallenge,
                challengeTitle: theirChallenge,
                sharedTags: shared)
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

    func refresh() async {
        guard case .ready = phase, let me = myID else { return }

        let incomingRecs = await queryFollows(field: "to", equals: me)      // edges → me
        let outgoingRecs = await queryFollows(field: "from", equals: me)    // edges from me
        let incomingFrom = Set(incomingRecs.compactMap { $0["from"] as? String }).subtracting(justRemoved)
        let outgoingTo   = Set(outgoingRecs.compactMap { $0["to"] as? String }).union(justFollowed).subtracting(justRemoved)

        let friendIds   = incomingFrom.intersection(outgoingTo)
        let ignored     = ignoredIncoming
        let incomingIds = incomingFrom.subtracting(outgoingTo).subtracting(ignored)
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
