import AppKit

enum NotchGeometry {
    /// L'écran avec un notch physique en priorité, sinon l'écran principal.
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: hasNotch) ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// Taille du notch physique. Pour un écran sans notch, renvoie une taille
    /// d'« île » par défaut.
    static func notchSize(for screen: NSScreen) -> CGSize {
        let top = screen.safeAreaInsets.top
        if top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return CGSize(width: width, height: top)
        }
        return CGSize(width: 185, height: 32)
    }
}
