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
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 10))
                        .foregroundColor(ColdPalette.grey)
                    Text("ROAST MODE · IDLE")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(ColdPalette.grey)
                        .tracking(1.4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(ColdPalette.edge, lineWidth: 0.5))

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Spacer()

            VStack(spacing: 20) {
                // Unlit match
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
                    .frame(width: 140, height: 140)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Nothing to burn yet.")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(ColdPalette.text)
                        .tracking(-0.5)

                    Text("Add a subject and keep every note organized privately in your roast library.")
                        .font(.system(size: 15))
                        .foregroundColor(ColdPalette.sub)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 280)
                }

                EmberCTAButton(title: "Light the first match", action: onAddTarget)
                    .padding(.top, 6)

                VStack(spacing: 2) {
                    Button {} label: {
                        Text("or import from Contacts")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ColdPalette.sub)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .disabled(true)
                    Text("coming soon")
                        .font(.system(size: 10))
                        .foregroundColor(ColdPalette.sub.opacity(0.7))
                        .tracking(0.3)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColdPalette.bg.ignoresSafeArea())
    }
}

/// Roast target list header.
struct RoastHomeHeader: View {
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
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
                .font(.system(size: small ? 10 : 14))
            Text("ROAST MODE")
                .font(.system(size: small ? 10 : 12, weight: .heavy))
                .tracking(1.4)
        }
        .foregroundColor(lit ? .white : ColdPalette.grey)
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
        HStack(alignment: .center, spacing: 12) {
            if let photoData = target.photoData, let img = UIImage(data: photoData) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(FirePalette.core)
                    Text(initials)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(safeName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(FirePalette.text)

                if !safeNotes.isEmpty {
                    Text(safeNotes)
                        .font(.system(size: 13))
                        .foregroundColor(FirePalette.sub)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(safeBits)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(FirePalette.text)
                    .monospacedDigit()
                Text(safeBits == 1 ? "burn" : "burns")
                    .font(.system(size: 12))
                    .foregroundColor(FirePalette.sub)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(FirePalette.sub.opacity(0.7))
        }
        .padding(14)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11ySummary)
        .accessibilityAddTraits(.isButton)
    }
}
