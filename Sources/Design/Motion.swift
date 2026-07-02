import SwiftUI

/// The app's one motion vocabulary — every animation routes through these tokens
/// so the whole app shares a single physical "feel".
enum Motion {
    /// Quick, matter-of-fact — selection changes, content swaps.
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// Playful overshoot — buttons releasing, elements landing.
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.68)
    /// Soft settle — entrances, blurs, ambient moves.
    static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.9)
    /// Springy appear — checkmarks, badges, swatches popping in.
    static let pop    = Animation.spring(response: 0.35, dampingFraction: 0.6)
}

// MARK: - Shimmer (one soft highlight sweep, then done)

private struct ShimmerPhase: ViewModifier, Animatable {
    var progress: CGFloat
    var strength: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.visualEffect { view, proxy in
            view.colorEffect(ShaderLibrary.shimmer(
                .float2(proxy.size), .float(progress), .float(strength)))
        }
    }
}

private struct ShimmerOnce: ViewModifier {
    var delay: Double
    var strength: CGFloat
    @State private var progress: CGFloat = -0.4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(ShimmerPhase(progress: progress, strength: strength))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).delay(delay)) { progress = 1.4 }
            }
    }
}

extension View {
    /// A single soft highlight sweep shortly after the view appears — never loops.
    func shimmerOnce(delay: Double = 0.6, strength: CGFloat = 0.35) -> some View {
        modifier(ShimmerOnce(delay: delay, strength: strength))
    }
}

// MARK: - Foil sweep (iridescent laminated-sticker sheen — shows on white, unlike shimmer)

private struct FoilPhase: ViewModifier, Animatable {
    var progress: CGFloat
    var strength: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.visualEffect { view, proxy in
            view.colorEffect(ShaderLibrary.foilSweep(
                .float2(proxy.size), .float(progress), .float(strength)))
        }
    }
}

private struct FoilOnce: ViewModifier {
    var delay: Double
    var strength: CGFloat
    @State private var progress: CGFloat = -0.4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(FoilPhase(progress: progress, strength: strength))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.3).delay(delay)) { progress = 1.4 }
            }
    }
}

extension View {
    /// One iridescent foil sweep (our pastels) shortly after appear — for the sticker card.
    func foilSweepOnce(delay: Double = 0.4, strength: CGFloat = 0.3) -> some View {
        modifier(FoilOnce(delay: delay, strength: strength))
    }
}

// MARK: - Skeleton shimmer (looping sweep for loading placeholders — the ONE allowed loop)

private struct SkeletonShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            // A sweep every 1.6s, travelling -0.4 → 1.4 so it fully clears the view.
            let phase = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            content.modifier(ShimmerPhase(progress: CGFloat(phase) * 1.8 - 0.4, strength: 0.55))
        }
    }
}

extension View {
    /// Looping highlight sweep for skeleton/loading placeholders. Pauses under Reduce Motion.
    func skeletonShimmer() -> some View {
        modifier(SkeletonShimmer())
    }
}

// MARK: - Ripple on tap (liquid pulse from the touch point)

private struct RippleShader: ViewModifier {
    var origin: CGPoint
    var elapsed: TimeInterval
    var duration: TimeInterval

    func body(content: Content) -> some View {
        content.layerEffect(
            ShaderLibrary.ripple(
                .float2(origin), .float(elapsed),
                .float(10),     // amplitude (pt)
                .float(14),     // frequency
                .float(7),      // decay
                .float(1400)),  // speed (pt/s)
            maxSampleOffset: CGSize(width: 10, height: 10),
            isEnabled: elapsed > 0 && elapsed < duration)
    }
}

private struct RippleOnTap: ViewModifier {
    var origin: CGPoint
    var trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let rm = reduceMotion
        return content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, elapsed in
            view.modifier(RippleShader(origin: origin,
                                       elapsed: rm ? 0 : elapsed,
                                       duration: 0.6))
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(0.6, duration: 0.6)
        }
    }
}

extension View {
    /// Runs the liquid ripple from `origin` (in the view's own coordinates) each time
    /// `trigger` increments. Zero cost while idle; respects Reduce Motion.
    func rippleOnTap(at origin: CGPoint, trigger: Int) -> some View {
        modifier(RippleOnTap(origin: origin, trigger: trigger))
    }
}

// MARK: - Crumple (paper crumples as `progress` goes 0 → 1)

struct CrumpleEffect: ViewModifier, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.layerEffect(
            ShaderLibrary.crumple(.float(progress), .float(7)),
            maxSampleOffset: CGSize(width: 34, height: 34),
            isEnabled: progress > 0)
    }
}

// MARK: - Staggered entrance (rows / cards cascading in, once per lifetime)

private struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .blur(radius: shown ? 0 : 3)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true; return }
                withAnimation(Motion.gentle.delay(Double(index) * 0.05)) { shown = true }
            }
    }
}

extension View {
    /// Fade-rise-unblur entrance, staggered by `index`. Fires once per view lifetime.
    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

// MARK: - Pop-in (badges / pills / floating accents arriving with a spring)

private struct PopIn: ViewModifier {
    var delay: Double
    var from: CGFloat
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : from)
            .opacity(shown ? 1 : 0)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true; return }
                withAnimation(Motion.pop.delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Springy scale-in entrance after `delay`. Fires once per view lifetime.
    func popIn(delay: Double = 0, from: CGFloat = 0.6) -> some View {
        modifier(PopIn(delay: delay, from: from))
    }
}
