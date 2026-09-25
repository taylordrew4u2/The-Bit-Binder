import AppKit
import SwiftUI

@main
struct ActionColorsRegression {
    static func main() {
        let appearances: [NSAppearance.Name] = [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua
        ]
        let fills = [("Blue", ActionColors.blue), ("Ember", ActionColors.ember)]

        for appearanceName in appearances {
            guard let appearance = NSAppearance(named: appearanceName) else {
                preconditionFailure("Missing appearance \(appearanceName)")
            }
            appearance.performAsCurrentDrawingAppearance {
                let foreground = rgb(ActionColors.foreground)
                precondition(foreground.alphaComponent == 1, "Labels must be opaque")
                for (name, fill) in fills {
                    let background = rgb(fill)
                    precondition(background.alphaComponent == 1, "\(name) fill must be opaque")
                    let contrast = contrastRatio(foreground, background)
                    precondition(
                        contrast >= 4.5,
                        "\(name) action has only \(contrast):1 contrast in \(appearanceName)"
                    )
                    print("\(name) / \(appearanceName.rawValue): \(String(format: "%.2f", contrast)):1")
                }
            }
        }
        print("Action color regression tests passed")
    }

    private static func rgb(_ color: Color) -> NSColor {
        guard let resolved = NSColor(color).usingColorSpace(.sRGB) else {
            preconditionFailure("Action colors must resolve to sRGB")
        }
        return resolved
    }

    private static func contrastRatio(_ first: NSColor, _ second: NSColor) -> Double {
        let firstLuminance = luminance(first)
        let secondLuminance = luminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private static func luminance(_ color: NSColor) -> Double {
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent)
            + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }
}
