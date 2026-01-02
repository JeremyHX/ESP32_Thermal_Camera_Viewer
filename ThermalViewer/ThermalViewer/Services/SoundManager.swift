import Foundation
import AudioToolbox
import AVFoundation
import UIKit

class SoundManager {
    static let shared = SoundManager()

    private var audioPlayer: AVAudioPlayer?

    private init() {
        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    /// Play a cheerful notification sound (reached desired temperature)
    func playReachedTemperatureSound() {
        // System sound 1025 is a pleasant tri-tone notification
        AudioServicesPlaySystemSound(1025)
        // Also provide haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Play an alert sound (temperature too high)
    func playOverheatAlertSound() {
        // System sound 1005 is an alarm/alert sound
        // Play it twice for emphasis
        AudioServicesPlaySystemSound(1005)
        // Provide warning haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        // Play again after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AudioServicesPlaySystemSound(1005)
        }
    }
}

/// Tracks temperature thresholds and triggers alerts when crossed
@Observable
class TemperatureAlertTracker {
    var soundAlertsEnabled: Bool = true

    private let lowThreshold: Double = 180
    private let highThreshold: Double = 250

    // Track which quadrants have already triggered each alert
    private var reachedLowThreshold: Set<String> = []
    private var reachedHighThreshold: Set<String> = []

    // Previous temperatures to detect crossing
    private var previousTemps: [String: Double] = [:]

    /// Check temperature and play sound if threshold is crossed going up
    func checkTemperature(quadrant: String, temperature: Double) {
        guard soundAlertsEnabled else { return }

        let previousTemp = previousTemps[quadrant] ?? 0
        previousTemps[quadrant] = temperature

        // Check if crossing 180°C going up
        if previousTemp < lowThreshold && temperature >= lowThreshold {
            if !reachedLowThreshold.contains(quadrant) {
                reachedLowThreshold.insert(quadrant)
                SoundManager.shared.playReachedTemperatureSound()
            }
        }

        // Reset low threshold flag if temp drops below
        if temperature < lowThreshold - 5 {
            reachedLowThreshold.remove(quadrant)
        }

        // Check if crossing 250°C going up
        if previousTemp < highThreshold && temperature >= highThreshold {
            if !reachedHighThreshold.contains(quadrant) {
                reachedHighThreshold.insert(quadrant)
                SoundManager.shared.playOverheatAlertSound()
            }
        }

        // Reset high threshold flag if temp drops below
        if temperature < highThreshold - 5 {
            reachedHighThreshold.remove(quadrant)
        }
    }

    /// Reset all tracking state
    func reset() {
        reachedLowThreshold.removeAll()
        reachedHighThreshold.removeAll()
        previousTemps.removeAll()
    }
}
