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
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? accentColor : .secondary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm - 2)
                .background(
                    RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous)
                        .fill(isSelected ? accentColor.opacity(DS.Opacity.light) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Corner.sm, style: .continuous)
                        .strokeBorder(isSelected ? accentColor.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 0.5)
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
    @AppStorage("roastTextScale") private var roastTextScale = 1.0
    let joke: RoastJoke
    let showFullContent: Bool
    let accentColor: Color
    var showsDragHandle: Bool = false
    var currentOpenerPosition: Int = 0

    private var bodyFont: CGFloat { 15 * roastTextScale }
    private var detailFont: CGFloat { 12 * roastTextScale }
    private var compactTitleFont: CGFloat { 15 * roastTextScale }

    private var compactTitle: String {
        joke.title.isEmpty
            ? KeywordTitleGenerator.displayTitle(from: joke.content)
            : joke.title
    }

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

            VStack(alignment: .leading, spacing: 6) {
                if showFullContent {
                    VStack(alignment: .leading, spacing: 10) {
                        if !joke.setup.isEmpty {
                            roastDetailBlock(title: "SETUP", text: joke.setup)
                        }

                        Text(joke.content)
                            .font(.system(size: bodyFont, weight: .regular))
                            .foregroundColor(FirePalette.text)
                            .fixedSize(horizontal: false, vertical: true)

                        if !joke.punchline.isEmpty {
                            roastDetailBlock(title: "PUNCHLINE", text: joke.punchline)
                        }

                        if !joke.performanceNotes.isEmpty {
                            roastDetailBlock(title: "NOTES", text: joke.performanceNotes)
                        }
                    }
                } else {
                    Text(compactTitle)
                        .font(.system(size: compactTitleFont, weight: .medium))
                        .foregroundColor(FirePalette.text)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    if joke.isOpeningRoast {
                        BadgePill(text: currentOpenerPosition > 0 ? "OPENER \(currentOpenerPosition)" : "OPENER", icon: "star.circle.fill", color: accentColor)
                    } else if joke.parentOpeningRoastID != nil {
                        BadgePill(text: "BACKUP", icon: "arrow.turn.down.right", color: accentColor)
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

    @ViewBuilder
    private func roastDetailBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundColor(accentColor)
            Text(text)
                .font(.system(size: detailFont, weight: .regular))
                .foregroundColor(FirePalette.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
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
