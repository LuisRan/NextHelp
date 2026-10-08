import SwiftUI
import AppKit

/// Controla cómo se comporta la ventana de la app:
///  • hiddenFromCapture → NSWindow.sharingType = .none: TÚ la ves, pero no sale
///    al compartir pantalla NI en capturas de pantalla de macOS (⇧⌘3 / ⇧⌘5).
///  • alwaysOnTop → flota encima de las ventanas de las demás apps y en todos
///    los escritorios, aunque des clic en otra app (ej. el navegador).
///  • opacity → transparencia de la ventana.
///
/// SwiftUI a veces reinicia el nivel de la ventana (al activar/desactivar la
/// app, al redimensionar…), así que los ajustes se REAPLICAN cada vez que
/// la ventana cambia de estado, no solo una vez.
struct WindowControl: NSViewRepresentable {
    let hiddenFromCapture: Bool
    let alwaysOnTop: Bool
    let opacity: Double

    func makeNSView(context: Context) -> WindowControlView { WindowControlView() }

    func updateNSView(_ view: WindowControlView, context: Context) {
        view.hiddenFromCapture = hiddenFromCapture
        view.alwaysOnTop = alwaysOnTop
        view.opacity = opacity
        view.apply()
    }
}

final class WindowControlView: NSView {
    var hiddenFromCapture = true
    var alwaysOnTop = false
    var opacity = 1.0
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        guard let window else { return }
        // Reaplicar cuando la ventana o la app cambian de estado.
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification,
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.apply()
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.apply()
        })
        apply()
    }

    func apply() {
        guard let window else { return }
        window.sharingType = hiddenFromCapture ? .none : .readOnly
        if alwaysOnTop {
            if window.level != .floating { window.level = .floating }
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.collectionBehavior.remove(.moveToActiveSpace)
            window.hidesOnDeactivate = false
        } else {
            if window.level != .normal { window.level = .normal }
            window.collectionBehavior.remove([.canJoinAllSpaces, .fullScreenAuxiliary])
        }
        window.alphaValue = CGFloat(opacity)
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
