import Foundation
import SwiftUI

enum ColorPalette: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case grayscale = "Grayscale"
    case inferno = "Inferno"
    case viridis = "Viridis"
    case plasma = "Plasma"
    case hot = "Hot"
    case fireice = "Fire & Ice"

    var id: String { rawValue }

    /// Get RGB color for a normalized value (0.0 to 1.0)
    func color(for value: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        let v = max(0, min(1, value))

        switch self {
        case .default:
            return defaultPalette(v)
        case .grayscale:
            return grayscalePalette(v)
        case .inferno:
            return infernoPalette(v)
        case .viridis:
            return viridisPalette(v)
        case .plasma:
            return plasmaPalette(v)
        case .hot:
            return hotPalette(v)
        case .fireice:
            return fireicePalette(v)
        }
    }

    // MARK: - Palette Implementations

    private func defaultPalette(_ v: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        // Blue (cold) -> Cyan -> Green -> Yellow -> Red (hot)
        if v < 0.25 {
            let t = v / 0.25
            return (r: 0, g: UInt8(t * 255), b: 255)
        } else if v < 0.5 {
            let t = (v - 0.25) / 0.25
            return (r: 0, g: 255, b: UInt8((1 - t) * 255))
        } else if v < 0.75 {
            let t = (v - 0.5) / 0.25
            return (r: UInt8(t * 255), g: 255, b: 0)
        } else {
            let t = (v - 0.75) / 0.25
            return (r: 255, g: UInt8((1 - t) * 255), b: 0)
        }
    }

    private func grayscalePalette(_ v: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        let gray = UInt8(v * 255)
        return (r: gray, g: gray, b: gray)
    }

    private func infernoPalette(_ v: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        // Black -> Purple -> Red -> Orange -> Yellow -> White
        if v < 0.2 {
            let t = v / 0.2
            return (r: UInt8(t * 60), g: 0, b: UInt8(t * 80))
        } else if v < 0.4 {
            let t = (v - 0.2) / 0.2
            return (r: UInt8(60 + t * 140), g: UInt8(t * 20), b: UInt8(80 - t * 40))
        } else if v < 0.6 {
            let t = (v - 0.4) / 0.2
            return (r: UInt8(200 + t * 55), g: UInt8(20 + t * 80), b: UInt8(40 - t * 40))
        } else if v < 0.8 {
            let t = (v - 0.6) / 0.2
            return (r: 255, g: UInt8(100 + t * 100), b: 0)
        } else {
            let t = (v - 0.8) / 0.2
            return (r: 255, g: UInt8(200 + t * 55), b: UInt8(t * 150))
        }
    }

    private func viridisPalette(_ v: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        // Dark purple -> Blue -> Teal -> Green -> Yellow
        if v < 0.25 {
            let t = v / 0.25
            return (r: UInt8(68 - t * 30), g: UInt8(1 + t * 50), b: UInt8(84 + t * 30))
        } else if v < 0.5 {
            let t = (v - 0.25) / 0.25
            return (r: UInt8(38 - t * 10), g: UInt8(51 + t * 60), b: UInt8(114 + t * 20))
        } else if v < 0.75 {
            let t = (v - 0.5) / 0.25
            return (r: UInt8(28 + t * 60), g: UInt8(111 + t * 70), b: UInt8(134 - t * 50))
        } else {
            let t = (v - 0.75) / 0.25
            return (r: UInt8(88 + t * 165), g: UInt8(181 + t * 50), b: UInt8(84 - t * 60))
        }
    }

    private func plasmaPalette(_ v: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        // Dark blue -> Purple -> Magenta -> Orange -> Yellow
        if v < 0.25 {
            let t = v / 0.25
            return (r: UInt8(13 + t * 80), g: UInt8(8 + t * 20), b: UInt8(135 + t * 30))
        } else if v < 0.5 {
            let t = (v - 0.25) / 0.25
            return (r: UInt8(93 + t * 100), g: UInt8(28 + t * 10), b: UInt8(165 - t * 30))
        } else if v < 0.75 {
            let t = (v - 0.5) / 0.25
            return (r: UInt8(193 + t * 50), g: UInt8(38 + t * 80), b: UInt8(135 - t * 80))
        } else {
            let t = (v - 0.75) / 0.25
            return (r: UInt8(243 + t * 12), g: UInt8(118 + t * 120), b: UInt8(55 - t * 35))
        }
    }

    private func hotPalette(_ v: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        // Black -> Red -> Yellow -> White
        if v < 0.33 {
            let t = v / 0.33
            return (r: UInt8(t * 255), g: 0, b: 0)
        } else if v < 0.66 {
            let t = (v - 0.33) / 0.33
            return (r: 255, g: UInt8(t * 255), b: 0)
        } else {
            let t = (v - 0.66) / 0.34
            return (r: 255, g: 255, b: UInt8(t * 255))
        }
    }

    private func fireicePalette(_ v: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        // Blue (cold) -> White (neutral) -> Red (hot)
        if v < 0.5 {
            let t = v / 0.5
            return (r: UInt8(t * 255), g: UInt8(t * 255), b: 255)
        } else {
            let t = (v - 0.5) / 0.5
            return (r: 255, g: UInt8((1 - t) * 255), b: UInt8((1 - t) * 255))
        }
    }
}

// MARK: - Color Palette Preview Colors

extension ColorPalette {
    var previewColors: [Color] {
        let steps = 10
        return (0..<steps).map { i in
            let value = Double(i) / Double(steps - 1)
            let (r, g, b) = color(for: value)
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
    }
}
