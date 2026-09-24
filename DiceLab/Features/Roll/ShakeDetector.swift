import SwiftUI

/// Shake-to-roll. SwiftUI has no shake gesture, and `deviceDidShakeNotification`
/// only posts when *nothing* handled the motion — fragile to depend on. The
/// deterministic pattern is an invisible first responder: motion events walk
/// the responder chain (object graph, not hit-test), so a zero-size view that
/// claims first responder receives `motionEnded` reliably.
struct ShakeDetector: UIViewRepresentable {
    let onShake: () -> Void

    func makeUIView(context: Context) -> ShakeView {
        ShakeView(onShake: onShake)
    }

    func updateUIView(_ uiView: ShakeView, context: Context) {
        uiView.onShake = onShake
        // Every SwiftUI update is a chance to take first responder back —
        // a presented sheet can claim it, and dismissing re-renders us.
        // The presentedViewController guard keeps us from stealing it
        // *while* a presentation is actually up.
        if uiView.window?.rootViewController?.presentedViewController == nil {
            uiView.becomeFirstResponder()
        }
    }

    final class ShakeView: UIView {
        var onShake: () -> Void

        init(onShake: @escaping () -> Void) {
            self.onShake = onShake
            super.init(frame: .zero)
            // Backgrounding transfers first responder to nothing reclaimable
            // by view lifecycle — re-claim when the app comes back.
            NotificationCenter.default.addObserver(
                self, selector: #selector(reclaimFirstResponder),
                name: UIApplication.didBecomeActiveNotification, object: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        deinit { NotificationCenter.default.removeObserver(self) }

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { becomeFirstResponder() }
        }

        @objc private func reclaimFirstResponder() {
            becomeFirstResponder()
        }

        override func motionEnded(_ motion: UIEvent.EventSubtype,
                                  with event: UIEvent?) {
            if motion == .motionShake { onShake() }
        }
    }
}
