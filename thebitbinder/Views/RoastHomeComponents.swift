//
//  RoastHomeComponents.swift
//  thebitbinder
//
//  Roast Mode v2 home-screen components, extracted from JokesView.
//

import SwiftUI
import SwiftData

// MARK: - Roast Mode v2 Components

/// Cold state — shown when there are zero roast subjects.
struct RoastColdStateView: View {
    let onAddTarget: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Label("Roast Mode · Idle", systemImage: "text.quote")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColdPalette.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 20) {
                    // The match is decorative; readable content gets the space
                    // as Dynamic Type grows and the whole state can scroll.
                    Image(systemName: "line.diagonal")
                        .font(.system(size: 60, weight: .thin))
                        .foregroundColor(ColdPalette.grey.opacity(0.7))
                        .rotationEffect(.degrees(-20))
                        .overlay(alignment: .top) {
                            Circle()
                                .fill(ColdPalette.grey)
                                .frame(width: 16, height: 16)
                                .offset(y: -10)
                        }
                        .frame(width: 100, height: 100)
                        .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        Text("Nothing to burn yet.")
                            .font(.title.weight(.bold))
                            .foregroundColor(ColdPalette.text)

                        Text("Add a subject and keep every note organized privately in your roast library.")
                            .font(.body)
                            .foregroundColor(ColdPalette.sub)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                    EmberCTAButton(title: "Add First Subject", action: onAddTarget)
                        .padding(.top, 6)
                }
                .padding(.vertical, 24)
                .frame(maxWidth: DS.readableWidth)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(ColdPalette.bg.ignoresSafeArea())
    }
}

/// Roast target list header.
struct RoastHomeHeader: View {
    @ScaledMetric(relativeTo: .headline) private var addButtonSize = 44.0
    let subjectCount: Int
    let onAddTarget: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Roasts")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(FirePalette.text)

                    Text("\(subjectCount) target\(subjectCount == 1 ? "" : "s")")
                        .font(.caption.weight(.medium))
                        .foregroundColor(FirePalette.sub)
                        .monospacedDigit()
                }

                Spacer()

                Button(action: onAddTarget) {
                    Image(systemName: "person.badge.plus")
                        .font(.headline)
                        .foregroundStyle(ActionColors.foreground)
                        .frame(width: addButtonSize, height: addButtonSize)
                        .background(FirePalette.emberCTA)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Add roast target")
            }

            Text("Targets, openers, and backup burns stay here until you exit Roast Mode.")
                .font(.footnote)
                .foregroundColor(FirePalette.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}

/// Roast Mode pill badge.
struct RoastModeBadge: View {
    var small: Bool = false
    var lit: Bool = true

    var body: some View {
        HStack(spacing: small ? 6 : 8) {
            Image(systemName: "text.quote")
                .accessibilityHidden(true)
            Text("ROAST MODE")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font((small ? Font.caption2 : Font.caption).weight(.heavy))
        .foregroundColor(lit ? ActionColors.foreground : ColdPalette.text)
        .padding(.horizontal, small ? 12 : 18)
        .padding(.vertical, small ? 6 : 10)
        .background(
            lit
                ? AnyShapeStyle(FirePalette.emberCTA)
                : AnyShapeStyle(Color.white.opacity(0.04))
        )
        .clipShape(Capsule())
        .overlay(
            lit ? nil : Capsule().strokeBorder(ColdPalette.edge, lineWidth: 0.5)
        )
    }
}

/// Subject card.
struct RoastSubjectCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var avatarSize = 44.0
    let target: RoastTarget

    private var safeName: String { target.isValid ? target.name : "" }
    private var safeNotes: String { target.isValid ? target.notes : "" }
    private var safeBits: Int { target.isValid ? target.jokeCount : 0 }

    private var initials: String {
        safeName.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
    }

    private var a11ySummary: String {
        var s = safeName
        if !safeNotes.isEmpty { s += ", \(safeNotes)" }
        s += ". \(safeBits) burn\(safeBits == 1 ? "" : "s")."
        return s
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        avatar
                        Spacer(minLength: 0)
                        chevron
                    }
                    targetDetails
                    Text("\(safeBits) \(safeBits == 1 ? "burn" : "burns")")
                        .font(.subheadline)
                        .foregroundColor(FirePalette.sub)
                        .monospacedDigit()
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    avatar
                    targetDetails
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(safeBits)")
                            .font(.headline)
                            .foregroundColor(FirePalette.text)
                            .monospacedDigit()
                        Text(safeBits == 1 ? "burn" : "burns")
                            .font(.caption)
                            .foregroundColor(FirePalette.sub)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    chevron
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FirePalette.card)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(FirePalette.edge, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11ySummary)
        .accessibilityAddTraits(.isButton)
    }

    private var targetDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(safeName)
                .font(.headline)
                .foregroundColor(FirePalette.text)

            if !safeNotes.isEmpty {
                Text(safeNotes)
                    .font(.subheadline)
                    .foregroundColor(FirePalette.sub)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var avatar: some View {
        Group {
            if let photoData = target.photoData, let img = UIImage(data: photoData) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(ActionColors.ember)
                    Text(initials)
                        .font(.headline)
                        .foregroundStyle(ActionColors.foreground)
                }
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundColor(FirePalette.sub)
            .accessibilityHidden(true)
    }
}
