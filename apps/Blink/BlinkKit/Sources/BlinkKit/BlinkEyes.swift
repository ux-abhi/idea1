// © Pexilim
import SwiftUI

/// Blink's panda duo-tone eyes, drawn in SwiftUI (no images, no Rive yet).
/// Sits on the black notch hardware; the patches are dark glass, the eyes carry the mood.
public struct BlinkEyes: View {
    public let mood: Mood
    /// Change to make Blink blink once (the preview's tap).
    public var blinkTrigger: Int
    /// Notch layout: the camera gap between the ears. The hardware is the patch, so no patches are drawn.
    public var notchGap: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pose: EyePose
    @State private var moodStart = Date.now
    @State private var blinking = false
    @State private var scale = 1.0
    @State private var thinkingFrozen = false
    @State private var burstStart: Date?

    public init(mood: Mood, blinkTrigger: Int = 0, notchGap: CGFloat? = nil) {
        self.mood = mood
        self.blinkTrigger = blinkTrigger
        self.notchGap = notchGap
        _pose = State(initialValue: mood.pose)
    }

    private var ambient: Bool {
        !reduceMotion && (mood == .listening || (mood == .thinking && !thinkingFrozen) || burstStart != nil)
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / Tokens.Motion.ambientFPS, paused: !ambient)) { context in
            let t = context.date.timeIntervalSince(moodStart)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    if let notchGap {
                        // One eye centred in each ear beside the camera.
                        let ear = max((w - notchGap) / 2, 0)
                        HStack(spacing: notchGap) {
                            eye(eyeW: h * 0.3, eyeH: h * 0.5, slot: CGSize(width: ear, height: h), t: t, mirrored: false, patch: false)
                            eye(eyeW: h * 0.3, eyeH: h * 0.5, slot: CGSize(width: ear, height: h), t: t, mirrored: true, patch: false)
                        }
                    } else {
                        HStack(spacing: w * 0.2) {
                            eye(eyeW: w * 0.15, eyeH: w * 0.25, slot: CGSize(width: w * 0.34, height: w * 0.42), t: t, mirrored: false, patch: true)
                            eye(eyeW: w * 0.15, eyeH: w * 0.25, slot: CGSize(width: w * 0.34, height: w * 0.42), t: t, mirrored: true, patch: true)
                        }
                    }
                    if let burstStart, !reduceMotion {
                        CelebrateBurst(progress: context.date.timeIntervalSince(burstStart) / Tokens.Motion.celebrateBurst.dur)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .bottom) {
            if mood == .thinking && thinkingFrozen {
                Text("Still working…").font(.caption).foregroundStyle(.white.opacity(0.8)).padding(.bottom, 6)
            }
        }
        .onChange(of: mood, initial: false) { _, new in enter(new) }
        .onChange(of: blinkTrigger) { Task { await blink() } }
        .task(id: mood) { await moodLoop() }
        .accessibilityElement()
        .accessibilityLabel("Blink")
        .accessibilityValue(mood == .thinking && thinkingFrozen ? "Still working" : mood.word)
    }

    private func eye(eyeW: CGFloat, eyeH: CGFloat, slot: CGSize, t: TimeInterval, mirrored: Bool, patch: Bool) -> some View {
        let side: CGFloat = mirrored ? 1 : -1
        var shown = pose
        if blinking { shown.openness = EyePose.closed.openness; shown.bite = 0 }
        if mirrored { shown.lidTilt = -shown.lidTilt }
        let motion = ambientMotion(t)

        return ZStack {
            if patch {
                // Panda patch: dark glass teardrop tilted outward.
                Ellipse()
                    .fill(LinearGradient(colors: [.gray.opacity(0.8), .gray.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                    .frame(width: slot.width * 0.94, height: slot.height * 0.95)
                    .rotationEffect(.degrees(Double(side) * 16))
            }
            EyeShape(pose: shown)
                .fill(mood.tint.color)
                // Soft-glow rim hugging the eye, so it reads against black even at notch size.
                .overlay {
                    EyeShape(pose: shown)
                        .stroke(mood.tint.color.opacity(Tokens.Glow.alpha), lineWidth: max(eyeW * 0.18, 1.5))
                        .blur(radius: max(eyeW * 0.12, 1))
                }
                .animation(.easeInOut(duration: Tokens.Motion.moodTint.dur), value: mood.tint)
                .shadow(color: mood.tint.color.opacity(Tokens.Glow.alpha), radius: Tokens.Glow.blur)
                .frame(width: eyeW, height: eyeH)
                .overlay(alignment: mirrored ? .topTrailing : .topLeading) {
                    if mood == .important { Circle().fill(.white).frame(width: eyeW * 0.28).offset(y: eyeH * 0.08) }
                }
                .scaleEffect(scale * motion.breath)
                .offset(x: motion.dx * eyeW, y: (shown.lookY + motion.dy) * eyeH)
        }
        .frame(width: slot.width, height: slot.height)
    }

    /// Thinking drifts its gaze in a 1.6 s cycle, slows at 10 s, freezes at 30 s; Listening breathes.
    private func ambientMotion(_ t: TimeInterval) -> (dx: Double, dy: Double, breath: Double) {
        guard !reduceMotion else { return (0, 0, 1) }
        let m = Tokens.Motion.self
        switch mood {
        case .thinking:
            let slow = m.thinkingSlowAfter
            let tt = min(t, m.thinkingFreezeAfter)
            let phase = tt < slow ? tt / m.thinkingCycle.dur : slow / m.thinkingCycle.dur + (tt - slow) / m.thinkingSlowDur
            let a = phase * 2 * .pi
            return (sin(a) * 0.18, -abs(cos(a)) * 0.05, 1)
        case .listening:
            // shortcut: simulated voice level; drive from the mic level when voice lands (Phase 2).
            return (0, 0, 1 + 0.04 * sin(t * 2 * .pi / 2.4))
        default:
            return (0, 0, 1)
        }
    }

    private func enter(_ new: Mood) {
        moodStart = .now
        thinkingFrozen = false
        burstStart = nil
        scale = 1
        let m = Tokens.Motion.self
        if reduceMotion {
            withAnimation(.easeInOut(duration: m.eyeShapeReduceMotion.dur)) { pose = new.pose }
            return
        }
        switch new {
        case .morning:
            pose = .closed
            withAnimation(.easeOut(duration: m.morningOpen.dur)) { pose = new.pose }
        case .sleepy:
            withAnimation(.easeInOut(duration: m.sleepyClose.dur)) { pose = new.pose }
        case .focus:
            withAnimation(m.focus.animation) { pose = new.pose }
        case .done, .celebrate:
            withAnimation(m.eyeShape.animation) { pose = new.pose }
            scale = 0.9
            withAnimation(m.success.animation) { scale = 1 }
            if new == .celebrate { burstStart = .now }
        case .important:
            withAnimation(m.eyeShape.animation) { pose = new.pose }
            withAnimation(.easeInOut(duration: m.importantPulse.dur / 2)) { scale = 1.12 } completion: {
                withAnimation(.easeInOut(duration: m.importantPulse.dur / 2)) { scale = 1 }
            }
        default:
            withAnimation(m.eyeShape.animation) { pose = new.pose }
        }
    }

    /// Timed parts of a mood: idle blinks, the thinking freeze, the end of the burst.
    private func moodLoop() async {
        let m = Tokens.Motion.self
        switch mood {
        case .idle:
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: m.blinkIntervalMin...m.blinkIntervalMax)))
                guard !Task.isCancelled else { return }
                await blink()
                if Double.random(in: 0..<1) < m.doubleBlinkChance { await blink() }
            }
        case .thinking:
            try? await Task.sleep(for: .seconds(m.thinkingFreezeAfter))
            if !Task.isCancelled { thinkingFrozen = true }
        case .celebrate:
            try? await Task.sleep(for: .seconds(m.celebrateBurst.dur))
            if !Task.isCancelled { burstStart = nil }
        default:
            return
        }
    }

    private func blink() async {
        let m = Tokens.Motion.self
        withAnimation(.easeIn(duration: m.blinkClose.dur)) { blinking = true }
        try? await Task.sleep(for: .seconds(m.blinkClose.dur))
        withAnimation(.easeOut(duration: m.blinkOpen.dur)) { blinking = false }
        try? await Task.sleep(for: .seconds(m.blinkOpen.dur))
    }
}

/// One eye: a pill that can widen, close, grow a ∩ (bite from below) and drop a sloped lid.
struct EyeShape: Shape {
    var pose: EyePose

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { .init(.init(pose.openness, pose.bite), .init(pose.lid, pose.lidTilt)) }
        set {
            pose.openness = newValue.first.first
            pose.bite = newValue.first.second
            pose.lid = newValue.second.first
            pose.lidTilt = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let h = max(rect.height * pose.openness, 1)
        let eye = CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        var path = Path(roundedRect: eye, cornerRadius: min(eye.width, h) / 2, style: .continuous)
        if pose.bite > 0.001 {
            let bw = eye.width * 0.7, bh = eye.height
            let top = eye.maxY - eye.height * 0.6 * pose.bite
            path = path.subtracting(Path(ellipseIn: CGRect(x: eye.midX - bw / 2, y: top, width: bw, height: bh)))
        }
        if pose.lid > 0.001 {
            let cut = eye.minY + eye.height * pose.lid
            let lid = Path(CGRect(x: eye.minX - eye.width, y: cut - eye.height * 2, width: eye.width * 3, height: eye.height * 2))
            let pivot = CGAffineTransform(translationX: eye.midX, y: cut)
                .rotated(by: pose.lidTilt * .pi / 180)
                .translatedBy(x: -eye.midX, y: -cut)
            path = path.subtracting(lid.applying(pivot))
        }
        return path
    }
}

/// ≤30 gold particles flying out once (Celebrate).
struct CelebrateBurst: View {
    let progress: Double

    var body: some View {
        Canvas { context, size in
            let p = min(max(progress, 0), 1)
            let eased = 1 - pow(1 - p, 3)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = min(size.width, size.height) * 0.6
            for i in 0..<Tokens.Motion.celebrateMaxParticles {
                let angle = Double(i) / Double(Tokens.Motion.celebrateMaxParticles) * 2 * .pi + Double(i % 3) * 0.2
                let r = reach * eased * (0.6 + 0.4 * Double((i * 7) % 5) / 4)
                let dot = CGRect(x: center.x + cos(angle) * r - 2, y: center.y + sin(angle) * r - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: dot), with: .color(MoodTint.celebrate.color.opacity(1 - p)))
            }
        }
        .allowsHitTesting(false)
    }
}
