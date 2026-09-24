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
    }

    final class ShakeView: UIView {
        var onShake: () -> Void

        init(onShake: @escaping () -> Void) {
            self.onShake = onShake
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { becomeFirstResponder() }
        }

        override func motionEnded(_ motion: UIEvent.EventSubtype,
                                  with event: UIEvent?) {
            if motion == .motionShake { onShake() }
        }
    }
}
