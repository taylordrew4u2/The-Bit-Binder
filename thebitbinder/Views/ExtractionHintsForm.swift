//
//  ExtractionHintsForm.swift
//  thebitbinder
//
//  Reusable SwiftUI form that binds to an `ExtractionHints` value. Used inline
//  inside the GagGrabber sheet and inside `ExtractionHintsPreflightSheet` when
//  a full-screen questionnaire is warranted.
//

import SwiftUI

struct ExtractionHintsForm: View {
    @Binding var hints: ExtractionHints

    /// When `true` the form renders in a tighter inline form (no header copy,
    /// no card backgrounds) suitable for embedding inside an existing List.
    var compact: Bool = false

    @State private var showAdvanced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 20) {
            if !compact {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before we grab…")
                        .font(.title3.weight(.semibold))
                    Text("A few quick answers help GagGrabber split your jokes cleanly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            chipGroup(
                title: "How are your bits separated?",
                selection: Binding(
                    get: { hints.separator },
                    set: { hints.separator = $0 }
                ),
                options: ExtractionHints.SeparatorStyle.allCases
            )

            chipGroup(
                title: "Typical length?",
                selection: Binding(
                    get: { hints.length },
                    set: { hints.length = $0 }
                ),
                options: ExtractionHints.BitLength.allCases
            )

            chipGroup(
                title: "What kind of document is this?",
                selection: Binding(
                    get: { hints.kind },
                    set: { hints.kind = $0 }
                ),
                options: ExtractionHints.DocumentKind.allCases
            )

            ignoreSection

            DisclosureGroup(isExpanded: $showAdvanced) {
                advancedSection
                    .padding(.top, 8)
            } label: {
                Text("More details (optional)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Chip group

    private func chipGroup<Option: Hashable & Identifiable>(
        title: String,
        selection: Binding<Option>,
        options: [Option]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            FlowLayout(spacing: 8) {
                ForEach(options) { option in
                    chip(
                        label: chipLabel(for: option),
                        icon: chipIcon(for: option),
                        isSelected: selection.wrappedValue == option
                    ) {
                        selection.wrappedValue = option
                    }
                }
            }
        }
    }

    private func chip(
        label: String,
        icon: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func chipLabel<Option: Hashable>(for option: Option) -> String {
        switch option {
        case let s as ExtractionHints.SeparatorStyle: return s.label
        case let l as ExtractionHints.BitLength:      return l.label
        case let k as ExtractionHints.DocumentKind:   return k.label
        default: return String(describing: option)
        }
    }

    private func chipIcon<Option: Hashable>(for option: Option) -> String? {
        switch option {
        case let s as ExtractionHints.SeparatorStyle: return s.sfSymbol
        case let k as ExtractionHints.DocumentKind:   return k.sfSymbol
        default: return nil
        }
    }

    // MARK: - Ignore toggles

    private var ignoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Anything to ignore?")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                toggleRow(
                    title: "Stage directions",
                    subtitle: "Skip [anything in square brackets]",
                    isOn: $hints.ignore.stageDirections
                )
                Divider().padding(.leading, 44)
                toggleRow(
                    title: "Crowd reactions",
                    subtitle: "Skip (laughs), (applause), (pause)",
                    isOn: $hints.ignore.crowdReactions
                )
                Divider().padding(.leading, 44)
                toggleRow(
                    title: "Timestamps",
                    subtitle: "Skip 00:00 / 01:23 markers",
                    isOn: $hints.ignore.timestamps
                )
                Divider().padding(.leading, 44)
                toggleRow(
                    title: "Notes to self",
                    subtitle: "Skip lines starting with note:, todo:, fixme:",
                    isOn: $hints.ignore.notesToSelf
                )
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Section label example")
                    .font(.subheadline.weight(.medium))
                Text("Paste a line you use to divide sections so GagGrabber treats it as a title, not a joke.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(#"e.g. "--- Act 2 ---""#, text: $hints.sectionLabelExample)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Anything else GagGrabber should know?")
                    .font(.subheadline.weight(.medium))
                TextField("Optional notes…", text: $hints.freeformNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - Flow layout for chips

/// Tiny flow layout — wraps chips onto new rows when they would overflow.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, x)
        }

        return CGSize(width: totalWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
