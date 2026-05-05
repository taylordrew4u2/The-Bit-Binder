//
//  RoastComponents.swift
//  thebitbinder
//
//  Shared roast-mode UI components used across roast target screens.
//

import SwiftUI

struct RoastSubjectAvatar: View {
    let photoData: Data?
    let fallbackInitial: String
    let accentColor: Color
    var size: CGFloat = 72

    var body: some View {
        AsyncAvatarView(
            photoData: photoData,
            size: size,
            fallbackInitial: fallbackInitial,
            accentColor: accentColor
        )
        .overlay(
            Circle()
                .stroke(accentColor.opacity(DS.Opacity.heavy), lineWidth: 2)
        )
    }
}

struct StatBadge: View {
    let count: Int
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(.caption)
            Text("\(count) \(label)\(count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xs)
        .padding(.vertical, DS.Spacing.xs + 1)
        .background(color)
        .clipShape(Capsule())
    }
}

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(isSelected ? .white : accentColor)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm - 2)
            .background(
                Capsule()
                    .fill(isSelected ? accentColor : accentColor.opacity(DS.Opacity.light))
            )
        }
        .buttonStyle(.plain)
    }
}

struct BadgePill: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(DS.Opacity.light))
        .clipShape(Capsule())
    }
}

struct RelatabilityScoreRow: View {
    let score: Int
    var maxScore: Int = 5
    var activeColor: Color = .bitbinderAccent
    var inactiveColor: Color = Color.gray.opacity(DS.Opacity.medium)

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<maxScore, id: \.self) { index in
                Circle()
                    .fill(index < score ? activeColor : inactiveColor)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Relatability")
        .accessibilityValue("\(score) out of \(maxScore)")
    }
}

struct RoastJokeCardContent: View {
    let joke: RoastJoke
    let showFullContent: Bool
    let accentColor: Color
    var showsDragHandle: Bool = false
    var onToggleKiller: (() -> Void)? = nil
    var onToggleTested: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            if showsDragHandle {
                VStack {
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary.opacity(DS.Opacity.heavy))
                        .frame(width: DS.Spacing.xl + DS.Spacing.xs)
                    Spacer()
                }
                .contentShape(Rectangle())
            }

            Button {
                onToggleKiller?()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Corner.md, style: .continuous)
                        .fill(joke.isKiller ? Color.bitbinderAccent.opacity(DS.Opacity.medium) : accentColor.opacity(DS.Opacity.light))
                        .frame(width: 44, height: 44)
                    Image(systemName: joke.isKiller ? "star.fill" : "flame.fill")
                        .font(.title3)
                        .foregroundColor(accentColor)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                if showFullContent {
                    Text(joke.content)
                        .font(.subheadline)
                        .foregroundColor(FirePalette.text)
                        .lineLimit(4)
                } else {
                    Text(joke.content.components(separatedBy: .newlines).first ?? joke.content)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(FirePalette.text)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    if joke.isOpeningRoast {
                        BadgePill(text: "OPENER", icon: "star.circle.fill", color: accentColor)
                    } else if joke.parentOpeningRoastID != nil {
                        BadgePill(text: "BACKUP", icon: "arrow.turn.down.right", color: accentColor)
                    }

                    if joke.isTested {
                        Button {
                            onToggleTested?()
                        } label: {
                            BadgePill(text: "\(joke.performanceCount)×", icon: "checkmark.circle.fill", color: accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    if joke.relatabilityScore > 0 {
                        RelatabilityScoreRow(score: joke.relatabilityScore, activeColor: accentColor)
                    }

                    Spacer()

                    Text(joke.dateCreated, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, DS.Spacing.xs)
        }
        .padding(DS.Spacing.md)
        .contentShape(Rectangle())
    }
}

struct RoastSelectionRow: View {
    let title: String
    var leadingNumber: Int? = nil
    var isSelected: Bool = false
    var accentColor: Color = .bitbinderAccent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm + 2) {
                if let leadingNumber {
                    Text("\(leadingNumber)")
                        .font(.subheadline.bold())
                        .foregroundColor(.black)
                        .frame(width: DS.Spacing.xxl, height: DS.Spacing.xxl)
                        .background(accentColor)
                        .clipShape(Circle())
                }

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(accentColor)
                }
            }
            .padding(DS.Spacing.md)
            .background(
                isSelected
                    ? accentColor.opacity(DS.Opacity.light)
                    : Color(UIColor.secondarySystemBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PerformanceQuickActions: View {
    let isKiller: Binding<Bool>
    let isTested: Binding<Bool>
    let performanceCount: Int
    let accentColor: Color
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            QuickToggleButton(
                isOn: isKiller,
                icon: "star.fill",
                label: "Killer",
                activeColor: accentColor
            )

            Divider()
                .frame(height: 30)

            QuickToggleButton(
                isOn: isTested,
                icon: "checkmark.circle.fill",
                label: "Tested",
                activeColor: accentColor
            )

            Divider()
                .frame(height: 30)

            Button(action: onDecrement) {
                VStack(spacing: 2) {
                    Image(systemName: "minus.circle")
                        .font(.subheadline)
                    Text("-1")
                        .font(.caption2)
                }
                .foregroundColor(performanceCount > 0 ? accentColor : .secondary.opacity(0.3))
                .frame(width: 44)
                .padding(.vertical, DS.Spacing.sm)
            }
            .buttonStyle(.plain)
            .disabled(performanceCount == 0)

            Button(action: onIncrement) {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.caption2.bold())
                        Text("\(performanceCount)")
                            .font(.subheadline.bold().monospacedDigit())
                    }
                    Text("Performed")
                        .font(.caption2)
                }
                .foregroundColor(performanceCount > 0 ? accentColor : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(Color(UIColor.secondarySystemBackground))
    }
}

struct PerformanceStatsCard: View {
    let performanceCount: Int
    let lastPerformedDate: Date?
    var accentColor: Color = .bitbinderAccent

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(accentColor)
                Text("Performance")
                    .font(.subheadline.bold())
                Spacer()
            }

            HStack(spacing: DS.Spacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(performanceCount)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundColor(accentColor)
                    Text("times")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let lastPerformedDate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lastPerformedDate, format: .dateTime.month(.abbreviated).day())
                            .font(.subheadline.bold())
                        Text("last performed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
        }
        .padding(DS.Spacing.md)
        .background(accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.md, style: .continuous))
        .padding(.horizontal, DS.Spacing.lg)
    }
}

struct RoastEditableAvatar: View {
    let uiImage: UIImage?
    let photoData: Data?
    let accentColor: Color
    var size: CGFloat = 100

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let photoData, let loadedImage = UIImage(data: photoData) {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(DS.Opacity.light))
                        .frame(width: size, height: size)
                    VStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.largeTitle)
                            .foregroundColor(accentColor)
                        Text("Add Photo")
                            .font(.caption2)
                            .foregroundColor(accentColor)
                    }
                }
            }
        }
        .overlay(
            Circle()
                .stroke(accentColor, lineWidth: 3)
        )
    }
}
