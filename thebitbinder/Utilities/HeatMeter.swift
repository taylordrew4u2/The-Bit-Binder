//
//  HeatMeter.swift
//  thebitbinder
//
//  Continuous heat bar for Roast Mode. Color scales with heat value:
//  0-30 ashy grey, 30-60 amber, 60-85 orange, 85-100 ember+glow.
//  Matches the Roast Mode v2 design spec.
//

import SwiftUI

struct HeatMeter: View {
    let value: Double

    var segments: Int = 8
    var segmentHeight: CGFloat = 10
    var gap: CGFloat = 3
    var glowWhenHot: Bool = true

    var body: some View {
        let clamped = min(max(value, 0), 1)
        let filledCount = Int(round(clamped * Double(segments)))
        let isHot = clamped >= 0.85

        ZStack {
            if isHot && glowWhenHot {
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

/// Continuous heat bar matching the v2 design — a single track with a
/// filled portion whose gradient shifts based on the heat value.
struct HeatBar: View {
    let heat: Int

    var body: some View {
        let clamped = min(max(heat, 0), 100)
        let pct = CGFloat(clamped) / 100.0

        let fill: LinearGradient = {
            if clamped < 30 {
                return LinearGradient(colors: [
                    Color(red: 0.35, green: 0.29, blue: 0.25),
                    Color(red: 0.48, green: 0.42, blue: 0.35)
                ], startPoint: .leading, endPoint: .trailing)
            } else if clamped < 60 {
                return LinearGradient(colors: [
                    Color(red: 0.54, green: 0.42, blue: 0.23),
                    FirePalette.bright
                ], startPoint: .leading, endPoint: .trailing)
            } else if clamped < 85 {
                return LinearGradient(colors: [
                    FirePalette.bright,
                    FirePalette.core
                ], startPoint: .leading, endPoint: .trailing)
            } else {
                return LinearGradient(colors: [
                    FirePalette.core,
                    Color(red: 1.0, green: 0.18, blue: 0.0)
                ], startPoint: .leading, endPoint: .trailing)
            }
        }()

        let glowShadow: Color = {
            if clamped < 60 { return .clear }
            if clamped < 85 { return FirePalette.core.opacity(0.33) }
            return FirePalette.core.opacity(0.67)
        }()

        let numColor: Color = {
            if clamped < 30 { return ColdPalette.grey }
            if clamped < 60 { return FirePalette.bright }
            return FirePalette.core
        }()

        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(FirePalette.text.opacity(0.06))

                    Capsule()
                        .fill(fill)
                        .frame(width: geo.size.width * pct)
                        .shadow(color: glowShadow, radius: clamped >= 60 ? 6 : 0)
                }
            }
            .frame(height: 4)

            Text("\(clamped)°")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(numColor)
                .monospacedDigit()
                .frame(minWidth: 32, alignment: .trailing)
        }
        .accessibilityElement()
        .accessibilityLabel("Heat")
        .accessibilityValue("\(clamped) degrees")
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        ForEach([0, 18, 34, 58, 76, 92], id: \.self) { h in
            HeatBar(heat: h)
                .frame(width: 260)
        }
    }
    .padding(32)
    .background(FirePalette.bg.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
