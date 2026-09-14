import AppKit
import SwiftUI

/* ─────────────────────────────────────────────────────────
 * ONBOARDING STORYBOARD
 *
 * Read top-to-bottom. Each value is ms after the view appears.
 *
 *    0ms   the dashboard dims behind the welcome card
 *   60ms   the welcome card fades in and settles upward
 *  180ms   the health mark springs into place; the chime plays
 *  330ms   the orbital rings draw around the health mark
 *  480ms   the welcome message rises into view
 *  620ms   health categories appear (staggered 60ms)
 *  760ms   setup actions fade in
 * ───────────────────────────────────────────────────────── */

private enum OnboardingTimeline {
    static let cardAppears = 60
    static let markAppears = 180
    static let orbitDraws = 330
    static let messageAppears = 480
    static let featuresAppear = 620
    static let actionsAppear = 760
}

private enum OnboardingPersistence {
    static let completionKey = "hasCompletedOnboarding.v1"
}

private enum OnboardingMotion {
    static let cardInitialScale = 0.94
    static let cardInitialOffset: CGFloat = 16
    static let markInitialScale = 0.72
    static let markInitialOffset: CGFloat = 10
    static let markInitialRotation = -8.0
    static let messageInitialOffset: CGFloat = 10
    static let featureInitialOffset: CGFloat = 8
    static let actionInitialOffset: CGFloat = 8
    static let featureStagger = 0.06
    static let cardSpring = Animation.spring(response: 0.46, dampingFraction: 0.86)
    static let markSpring = Animation.spring(response: 0.5, dampingFraction: 0.72)
    static let orbitAnimation = Animation.easeOut(duration: 0.52)
    static let entranceAnimation = Animation.easeOut(duration: 0.32)
    static let reducedAnimation = Animation.easeOut(duration: 0.16)
    static let exitAnimation = Animation.easeOut(duration: 0.16)
}

private enum OnboardingLayout {
    static let cardRadius: CGFloat = 28
    static let cardPadding: CGFloat = 28
    static let cardWidth: CGFloat = 364
    static let markSize: CGFloat = 88
    static let markRadius: CGFloat = 25
    static let orbitSize: CGFloat = 142
    static let haloSize: CGFloat = 126
    static let backdropOpacityLight = 0.46
    static let backdropOpacityDark = 0.58
}

private struct OnboardingFeature: Identifiable {
    let id: String
    let symbol: String
    let color: Color

    static let all = [
        OnboardingFeature(id: "Sleep", symbol: "moon.stars.fill", color: .indigo),
        OnboardingFeature(id: "Heart", symbol: "heart.fill", color: .pink),
        OnboardingFeature(id: "Activity", symbol: "figure.walk", color: .orange)
    ]
}

private enum OnboardingSound {
    static let welcome: NSSound? = {
        guard let sound = NSSound(named: NSSound.Name("Glass")) else { return nil }
        sound.volume = 0.28
        return sound
    }()

    static func play() {
        welcome?.stop()
        welcome?.play()
    }
}

struct OnboardingContainer<Content: View>: View {
    @ObservedObject private var store: AppStore
    private let content: Content
    private let shouldPersistCompletion: Bool
    @State private var isPresented: Bool

    init(store: AppStore, content: Content) {
        self.store = store
        self.content = content

        let arguments = ProcessInfo.processInfo.arguments
        let isPreview = arguments.contains("--snapshot") || arguments.contains("--demo") || arguments.contains("--ui-smoke")
        let isForced = arguments.contains("--onboarding")
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: OnboardingPersistence.completionKey)
        _isPresented = State(initialValue: isForced || (!isPreview && !store.isConnected && isFirstLaunch))
        shouldPersistCompletion = !isPreview && !isForced
    }

    var body: some View {
        ZStack {
            content
                .allowsHitTesting(!isPresented)
                .disabled(isPresented)
                .accessibilityHidden(isPresented)

            if isPresented {
                OnboardingView(
                    playSound: shouldPersistCompletion,
                    connect: { finish(then: store.connect) },
                    preview: { finish(then: store.preview) },
                    dismiss: { finish() }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    private func finish(then action: (() -> Void)? = nil) {
        if shouldPersistCompletion {
            UserDefaults.standard.set(true, forKey: OnboardingPersistence.completionKey)
        }
        withAnimation(OnboardingMotion.exitAnimation) { isPresented = false }
        if let action {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.17, execute: action)
        }
    }
}

private struct OnboardingView: View {
    let playSound: Bool
    let connect: () -> Void
    let preview: () -> Void
    let dismiss: () -> Void

    @AccessibilityPreferences private var accessibility
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var primaryActionFocused: Bool
    @State private var stage = 0
    @State private var hasPlayedSound = false

    private var backdropOpacity: Double {
        colorScheme == .dark ? OnboardingLayout.backdropOpacityDark : OnboardingLayout.backdropOpacityLight
    }

    private var stageAnimation: Animation {
        accessibility.reduceMotion ? OnboardingMotion.reducedAnimation : OnboardingMotion.entranceAnimation
    }

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            welcomeCard
                .opacity(stage >= 1 ? 1 : 0)
                .scaleEffect(accessibility.reduceMotion || stage >= 1 ? 1 : OnboardingMotion.cardInitialScale)
                .offset(y: accessibility.reduceMotion || stage >= 1 ? 0 : OnboardingMotion.cardInitialOffset)
                .animation(accessibility.reduceMotion ? OnboardingMotion.reducedAnimation : OnboardingMotion.cardSpring, value: stage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onExitCommand(perform: dismiss)
        .task { await playStoryboard() }
        .accessibilityAddTraits(.isModal)
    }

    private var welcomeCard: some View {
        VStack(spacing: 22) {
            healthMark

            VStack(spacing: 8) {
                Text("Welcome to Air Stats")
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Text("Your Fitbit essentials, tucked quietly\ninto the menu bar.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
            }
            .opacity(stage >= 4 ? 1 : 0)
            .offset(y: accessibility.reduceMotion || stage >= 4 ? 0 : OnboardingMotion.messageInitialOffset)
            .animation(stageAnimation, value: stage)

            HStack(spacing: 8) {
                ForEach(Array(OnboardingFeature.all.enumerated()), id: \.element.id) { index, feature in
                    featurePill(feature)
                        .opacity(stage >= 5 ? 1 : 0)
                        .offset(y: accessibility.reduceMotion || stage >= 5 ? 0 : OnboardingMotion.featureInitialOffset)
                        .animation(stageAnimation.delay(Double(index) * OnboardingMotion.featureStagger), value: stage)
                }
            }

            VStack(spacing: 10) {
                Button(action: connect) {
                    Label("Connect with Google", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .foregroundStyle(.white)
                }
                .modifier(PrimaryButtonStyle())
                .controlSize(.large)
                .focused($primaryActionFocused)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding-connect")

                Button("Preview sample data", action: preview)
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .accessibilityIdentifier("onboarding-preview")

                Button("Not now", action: dismiss)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .accessibilityIdentifier("onboarding-dismiss")
            }
            .font(.system(size: 13))
            .disabled(stage < 6)
            .opacity(stage >= 6 ? 1 : 0)
            .offset(y: accessibility.reduceMotion || stage >= 6 ? 0 : OnboardingMotion.actionInitialOffset)
            .animation(stageAnimation, value: stage)

            Label("Read-only access · credentials stay in Keychain", systemImage: "lock.shield")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(stage >= 6 ? 1 : 0)
                .animation(stageAnimation, value: stage)
        }
        .padding(OnboardingLayout.cardPadding)
        .frame(width: OnboardingLayout.cardWidth)
        .background { cardBackground }
        .overlay {
            RoundedRectangle(cornerRadius: OnboardingLayout.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(accessibility.increasedContrast ? 0.28 : 0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 30, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Air Stats")
    }

    @ViewBuilder private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: OnboardingLayout.cardRadius, style: .continuous)
        if accessibility.reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else {
            shape
                .fill(.regularMaterial)
                .background {
                    shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
                }
        }
    }

    private var healthMark: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.green.opacity(0.2), Color.cyan.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: OnboardingLayout.haloSize / 2
                    )
                )
                .frame(width: OnboardingLayout.haloSize, height: OnboardingLayout.haloSize)
                .scaleEffect(accessibility.reduceMotion || stage >= 2 ? 1 : 0.72)
                .opacity(stage >= 2 ? 1 : 0)

            Circle()
                .trim(from: 0.08, to: stage >= 3 ? 0.82 : 0.08)
                .stroke(
                    AngularGradient(colors: [.green.opacity(0.2), .cyan.opacity(0.9), .green.opacity(0.2)], center: .center),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .frame(width: OnboardingLayout.orbitSize, height: OnboardingLayout.orbitSize)
                .rotationEffect(.degrees(-36))
                .opacity(stage >= 3 ? 1 : 0)
                .animation(accessibility.reduceMotion ? OnboardingMotion.reducedAnimation : OnboardingMotion.orbitAnimation, value: stage)

            Circle()
                .trim(from: 0.55, to: stage >= 3 ? 0.96 : 0.55)
                .stroke(Color.green.opacity(0.34), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .frame(width: OnboardingLayout.orbitSize - 18, height: OnboardingLayout.orbitSize - 18)
                .rotationEffect(.degrees(24))
                .opacity(stage >= 3 ? 1 : 0)
                .animation(accessibility.reduceMotion ? OnboardingMotion.reducedAnimation : OnboardingMotion.orbitAnimation.delay(0.06), value: stage)

            RoundedRectangle(cornerRadius: OnboardingLayout.markRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.16, green: 0.78, blue: 0.48), Color(red: 0.05, green: 0.58, blue: 0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: OnboardingLayout.markSize, height: OnboardingLayout.markSize)
                .overlay {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.monochrome)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: OnboardingLayout.markRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.26), lineWidth: 1)
                }
                .shadow(color: .green.opacity(0.28), radius: 18, y: 8)
                .scaleEffect(accessibility.reduceMotion || stage >= 2 ? 1 : OnboardingMotion.markInitialScale)
                .rotationEffect(.degrees(accessibility.reduceMotion || stage >= 2 ? 0 : OnboardingMotion.markInitialRotation))
                .offset(y: accessibility.reduceMotion || stage >= 2 ? 0 : OnboardingMotion.markInitialOffset)
                .opacity(stage >= 2 ? 1 : 0)
                .animation(accessibility.reduceMotion ? OnboardingMotion.reducedAnimation : OnboardingMotion.markSpring, value: stage)
        }
        .frame(height: OnboardingLayout.orbitSize)
        .accessibilityHidden(true)
    }

    private func featurePill(_ feature: OnboardingFeature) -> some View {
        Label {
            Text(feature.id).foregroundStyle(.primary)
        } icon: {
            Image(systemName: feature.symbol).foregroundStyle(feature.color)
        }
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(feature.color.opacity(0.1), in: Capsule())
            .overlay { Capsule().strokeBorder(feature.color.opacity(0.14), lineWidth: 0.5) }
    }

    @MainActor private func playStoryboard() async {
        if accessibility.reduceMotion {
            withAnimation(OnboardingMotion.reducedAnimation) { stage = 6 }
            playWelcomeSoundIfNeeded()
            primaryActionFocused = true
            return
        }

        guard await advance(to: 1, at: OnboardingTimeline.cardAppears, after: 0) else { return }
        guard await advance(to: 2, at: OnboardingTimeline.markAppears, after: OnboardingTimeline.cardAppears) else { return }
        playWelcomeSoundIfNeeded()
        guard await advance(to: 3, at: OnboardingTimeline.orbitDraws, after: OnboardingTimeline.markAppears) else { return }
        guard await advance(to: 4, at: OnboardingTimeline.messageAppears, after: OnboardingTimeline.orbitDraws) else { return }
        guard await advance(to: 5, at: OnboardingTimeline.featuresAppear, after: OnboardingTimeline.messageAppears) else { return }
        guard await advance(to: 6, at: OnboardingTimeline.actionsAppear, after: OnboardingTimeline.featuresAppear) else { return }
        primaryActionFocused = true
    }

    @MainActor private func advance(to nextStage: Int, at time: Int, after previousTime: Int) async -> Bool {
        let milliseconds = max(0, time - previousTime)
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
        guard !Task.isCancelled else { return false }
        stage = nextStage
        return true
    }

    @MainActor private func playWelcomeSoundIfNeeded() {
        guard playSound, !hasPlayedSound else { return }
        hasPlayedSound = true
        OnboardingSound.play()
    }
}
