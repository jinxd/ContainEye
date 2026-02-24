import Foundation
import UIKit

@MainActor
final class TerminalShakeInputController {
    private weak var hostView: UIView?
    private var detectorView: ShakeDetectorView?
    private var onShake: (() -> Void)?

    func start(in view: UIView, onShake: @escaping () -> Void) {
        self.onShake = onShake
        hostView = view

        let detector: ShakeDetectorView
        if let existing = detectorView {
            detector = existing
        } else {
            detector = ShakeDetectorView(frame: .zero)
            detector.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            detector.backgroundColor = .clear
            detector.isUserInteractionEnabled = false
            detector.onShake = { [weak self] in
                self?.onShake?()
            }
            detectorView = detector
        }

        if detector.superview !== view {
            detector.frame = view.bounds
            view.addSubview(detector)
        }

        detector.becomeActiveFirstResponder()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        detectorView?.resignFirstResponder()
        detectorView?.removeFromSuperview()
        detectorView = nil
        hostView = nil
        onShake = nil
    }

    @objc
    private func handleDidBecomeActive() {
        detectorView?.becomeActiveFirstResponder()
    }
}

private final class ShakeDetectorView: UIView {
    var onShake: (() -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    func becomeActiveFirstResponder() {
        _ = becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else {
            super.motionEnded(motion, with: event)
            return
        }
        onShake?()
    }
}
