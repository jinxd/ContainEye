import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class TerminalHardwareInputController: NSObject, ObservableObject {
    private var volumeView: MPVolumeView?
    private var slider: UISlider?
    private var baselineVolume: Float = 0.5
    private var isObserving = false
    private var volumeObservation: NSKeyValueObservation?
    private var onVolumeDown: (() -> Void)?
    private var onVolumeUp: (() -> Void)?

    func start(onVolumeDown: @escaping () -> Void, onVolumeUp: @escaping () -> Void) {
        guard !isObserving else {
            self.onVolumeDown = onVolumeDown
            self.onVolumeUp = onVolumeUp
            return
        }

        self.onVolumeDown = onVolumeDown
        self.onVolumeUp = onVolumeUp

        let offscreenOrigin = CGPoint(x: -UIFloat(2000), y: -UIFloat(2000))
        let hiddenSize = CGSize(width: UIFloat(10), height: UIFloat(10))
        let volumeView = MPVolumeView(frame: CGRect(origin: offscreenOrigin, size: hiddenSize))
        volumeView.isHidden = true
        self.volumeView = volumeView

        let slider = volumeView.subviews.compactMap { $0 as? UISlider }.first
        self.slider = slider

        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            // Best-effort only.
        }

        if let slider {
            baselineVolume = min(0.9, max(0.1, slider.value))
            slider.value = baselineVolume
        }

        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self, let volume = change.newValue else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handleVolumeChange(volume)
            }
        }
        isObserving = true
    }

    func stop() {
        if isObserving {
            volumeObservation?.invalidate()
            volumeObservation = nil
            isObserving = false
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: [])

        volumeView?.removeFromSuperview()
        volumeView = nil
        slider = nil
        onVolumeDown = nil
        onVolumeUp = nil
    }

    private func handleVolumeChange(_ volume: Float) {
        if volume < baselineVolume {
            onVolumeDown?()
        } else if volume > baselineVolume {
            onVolumeUp?()
        }

        slider?.value = baselineVolume
    }

    deinit {
        if isObserving {
            volumeObservation?.invalidate()
            volumeObservation = nil
            isObserving = false
        }
    }
}
