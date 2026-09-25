import SwiftUI

@main
struct TextSizeRegression {
    static func main() {
        let standardSizes: [DynamicTypeSize] = [
            .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge
        ]
        let accessibilitySizes: [DynamicTypeSize] = [
            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
        ]

        for systemSize in standardSizes + accessibilitySizes {
            expect(
                AppTextSize.system.resolvedDynamicTypeSize(systemSize: systemSize) == systemSize,
                "System must follow every system size, including accessibility sizes"
            )
        }

        for preference in AppTextSize.allCases {
            for systemSize in accessibilitySizes {
                expect(
                    preference.resolvedDynamicTypeSize(systemSize: systemSize) == systemSize,
                    "\(preference) must preserve \(systemSize)"
                )
            }
        }

        let existingPreferences: [(String, AppTextSize, DynamicTypeSize)] = [
            ("small", .small, .small),
            ("standard", .standard, .large),
            ("large", .large, .xLarge),
            ("extraLarge", .extraLarge, .xxLarge)
        ]
        for (rawValue, preference, resolvedSize) in existingPreferences {
            expect(AppTextSize(rawValue: rawValue) == preference, "Keep existing stored preferences readable")
            for systemSize in standardSizes {
                expect(
                    preference.resolvedDynamicTypeSize(systemSize: systemSize) == resolvedSize,
                    "Explicit \(preference) should still apply at standard system sizes"
                )
            }
            // Selecting accessibility sizing must not rewrite an explicit choice:
            // it takes effect again after the system returns to a standard size.
            _ = preference.resolvedDynamicTypeSize(systemSize: .accessibility5)
            expect(preference.rawValue == rawValue, "Keep the user's saved explicit choice")
            expect(
                preference.resolvedDynamicTypeSize(systemSize: .large) == resolvedSize,
                "Restore explicit preference when leaving accessibility sizing"
            )
        }

        expect(AppTextSize.allCases.first == .system, "Offer System first in settings")
        print("Text size regression tests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
