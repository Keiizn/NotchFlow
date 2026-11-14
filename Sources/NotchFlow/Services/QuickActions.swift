import AppKit
import IOKit.pwr_mgt

/// Actions rapides du système + Raccourcis (app Shortcuts).
@MainActor
final class QuickActions: ObservableObject {
    static let shared = QuickActions()

    @Published private(set) var shortcuts: [String] = []
    @Published private(set) var isLoadingShortcuts = false
    @Published private(set) var isCaffeinated = false
    @Published private(set) var desktopHidden = false
    @Published private(set) var isDarkMode = false
    @Published var lastRun: String?

    private var assertionID: IOPMAssertionID = 0

    private init() {
        refreshStates()
    }

    func refreshStates() {
        isDarkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        desktopHidden = (UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool) == false
    }

    // MARK: - Raccourcis

    func loadShortcuts() {
        guard !isLoadingShortcuts else { return }
        isLoadingShortcuts = true
        Task {
            let output = await Self.output("/usr/bin/shortcuts", ["list"])
            shortcuts = output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            isLoadingShortcuts = false
        }
    }

    func runShortcut(_ name: String) {
        lastRun = name
        Task {
            _ = await Self.output("/usr/bin/shortcuts", ["run", name])
            if lastRun == name { lastRun = nil }
        }
    }

    func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Actions système

    func lockScreen() {
        typealias LockFunction = @convention(c) () -> Int32
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(symbol, to: LockFunction.self)()
        } else {
            sleepDisplay()
        }
    }

    func sleepDisplay() {
        Task { _ = await Self.output("/usr/bin/pmset", ["displaysleepnow"]) }
    }

    func screenshot() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.screenshot.launcher") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            Task { _ = await Self.output("/usr/sbin/screencapture", ["-iUc"]) }
        }
    }

    func toggleDarkMode() {
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        Task.detached {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            await MainActor.run { QuickActions.shared.refreshStatesSoon() }
        }
    }

    func toggleDesktopIcons() {
        let show = desktopHidden
        Task {
            _ = await Self.output("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", show ? "true" : "false"])
            _ = await Self.output("/usr/bin/killall", ["Finder"])
            desktopHidden = !show
        }
    }

    /// Empêche la mise en veille de l'écran (comme `caffeinate`).
    func toggleCaffeine() {
        if isCaffeinated {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isCaffeinated = false
        } else {
            let result = IOPMAssertionCreateWithName(
                "PreventUserIdleDisplaySleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "NotchFlow : anti-veille" as CFString,
                &assertionID
            )
            isCaffeinated = result == 0
        }
    }

    func refreshStatesSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            refreshStates()
        }
    }

    // MARK: - Utilitaire

    nonisolated static func output(_ path: String, _ arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "")
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}
