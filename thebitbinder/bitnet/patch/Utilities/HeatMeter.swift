//
//  HeatMeter.swift
//  thebitbinder
//
//  A horizontal heat meter for Roast Mode surfaces. Visualizes how
//  "hot" a roast target is based on a 0…1 value (recency × frequency).
//  Segments light up from left to right using FirePalette.heat() so the
//  hottest targets glow with the `spark` tone and cool targets stay at
//  a dim ember.
//
//  Use it on RoastTargetDetailView hero cards and in the target list
//  row to replace generic progress bars. Pair with `.flame.fill` badges
//  when the heat exceeds 0.85 to call out the hottest target.
//

import SwiftUI

struct HeatMeter: View {
    /// 0…1 heat value. Values above 1 are clamped and trigger the
    /// "boiling" glow overlay.
    let value: Double

    /// Number of segmented notches. 8 is a good default at card width;
    /// drop to 5 for compact rows.
    var segments: Int = 8

    /// Height of a single segment. Meter height = segmentHeight.
    var segmentHeight: CGFloat = 10

    /// Gap between segments.
    var gap: CGFloat = 3

    /// If true, emit a soft halo below the meter when heat >= 0.85.
    /// Use on hero cards; turn off in dense list rows.
    var glowWhenHot: Bool = true

    var body: some View {
        let clamped = min(max(value, 0), 1)
        let filledCount = Int(round(clamped * Double(segments)))
        let isHot = clamped >= 0.85

        ZStack {
            if isHot && glowWhenHot {
                // Soft under-glow — pulls from the same warm tone as the
                // last filled segment so the meter "breathes heat".
                Capsule()
                    .fill(FirePalette.spark.opacity(0.35))
                    .blur(radius: 14)
                    .frame(height: segmentHeight * 2)
                    .transition(.opacity)
            }

            HStack(spacing: gap) {
                ForEach(0..<segments, id: \.self) { i in
                    let t = Double(i) / Double(max(segments - 1, 1))
                    let isFilled = i < filledCount
                    RoundedRectangle(cornerRadius: segmentHeight / 2, style: .continuous)
                        .fill(
                            isFilled
                              ? AnyShapeStyle(FirePalette.heat(t))
                              : AnyShapeStyle(Color.primary.opacity(0.08))
                        )
                        .frame(height: segmentHeight)
                        .animation(.easeOut(duration: 0.25).delay(Double(i) * 0.02), value: filledCount)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Heat")
        .accessibilityValue("\(Int(clamped * 100)) percent")
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        ForEach([0.0, 0.2, 0.5, 0.75, 0.92, 1.0], id: \.self) { v in
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "%.0f%%", v * 100))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                HeatMeter(value: v)
                    .frame(width: 220)
            }
        }
    }
    .padding(32)
    .background(FirePalette.ambient.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
