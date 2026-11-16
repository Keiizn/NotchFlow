import AppKit
import SwiftUI

/// Île affichée sur l'écran verrouillé pendant le déverrouillage facial.
@MainActor
final class LockScreenOverlay {
    static let shared = LockScreenOverlay()

    private var window: NSPanel?
    private var screenID: CGDirectDisplayID?
    private(set) var isVisible = false

    /// Prépare la fenêtre à l'avance : en créer une pendant le verrouillage échoue parfois.
    func prepare() {
        guard let screen = NotchGeometry.targetScreen() else { return }
        if window != nil, screenID == screen.displayID { return }
        window?.orderOut(nil)

        let notch = NotchGeometry.notchSize(for: screen)
        let size = NSSize(width: 460, height: 150)
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.canBecomeVisibleWithoutLogin = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0

        let root = LockScreenIslandView(notch: notch, hasNotch: NotchGeometry.hasNotch(screen))
            .environmentObject(FaceUnlockService.shared)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setFrame(frame, display: false)
        window = panel
        screenID = screen.displayID
    }

    /// Affiche l'île sur l'écran verrouillé. Renvoie false si l'API système est indisponible.
    @discardableResult
    func show() -> Bool {
        guard LockScreenSpace.shared.isAvailable else { return false }
        prepare()
        guard let window else { return false }
        window.orderFrontRegardless()
        LockScreenSpace.shared.attach(window)
        window.alphaValue = 1
        isVisible = true
        return true
    }

    /// Rattache la fenêtre (le système la retire parfois après la mise en veille de l'écran).
    func refresh() {
        guard isVisible, let window else { return }
        window.orderFrontRegardless()
        LockScreenSpace.shared.attach(window)
    }

    func hide() {
        guard let window else { return }
        isVisible = false
        window.alphaValue = 0
        LockScreenSpace.shared.detach(window)
        window.orderOut(nil)
    }
}

private struct LockScreenIslandView: View {
    @EnvironmentObject private var face: FaceUnlockService
    let notch: CGSize
    let hasNotch: Bool

    private var expanded: Bool { face.phase != .idle }

    private var width: CGFloat {
        expanded ? max(notch.width + 130, 330) : notch.width + 76
    }

    private var height: CGFloat {
        expanded ? notch.height + 60 : notch.height
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: hasNotch ? 8 : 0, bottomRadius: expanded ? 24 : 12)
                    .fill(Color.black)

                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: face.isArmed ? "lock.fill" : "lock.slash.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        statusIcon
                    }
                    .frame(height: notch.height)
                    .padding(.horizontal, 14)

                    if expanded {
                        message
                            .padding(.horizontal, 18)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                    }
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { face.trigger(manual: true) }
            .padding(.top, hasNotch ? 0 : 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: face.phase)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch face.phase {
        case .idle, .scanning:
            Image(systemName: "faceid")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(face.phase == .scanning ? .white : .white.opacity(0.5))
                .symbolEffect(.pulse, isActive: face.phase == .scanning)
        case .recognized:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: face.phase)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)
        case .paused:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var message: some View {
        HStack(spacing: 10) {
            switch face.phase {
            case .scanning:
                ProgressView().controlSize(.small).tint(.white)
                Text(face.liveness == .blink && face.faceVisible ? "Cligne des yeux" : (face.faceVisible ? "Analyse…" : "Regarde l'écran"))
            case .recognized(let name):
                Text("Bonjour, \(name)")
            case .failed(let reason):
                Text(reason)
                Spacer(minLength: 4)
                Text("Toucher pour réessayer").foregroundStyle(.white.opacity(0.5))
            case .paused(let reason):
                Text(reason)
            case .idle:
                EmptyView()
            }
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
