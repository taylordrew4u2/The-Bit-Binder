//
//  ExtractionProviderBadge.swift
//  thebitbinder
//
//  Small info chip shown at the top of the import review sheet so the user
//  can see *which* GagGrabber provider actually ran. Pulls the displayable
//  label + icon from the string `ImportPipelineResult.providerUsed` carries
//  back from the pipeline (which is `AIProviderType.displayName`, or
//  "Multiple" / "Unknown" for aggregated multi-file imports).
//

import SwiftUI

struct ExtractionProviderBadge: View {
    let providerUsed: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(tagline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Mapping

    /// `providerUsed` comes from the pipeline as `AIProviderType.displayName`
    /// or the aggregation labels "Multiple" / "Unknown". Match by displayName
    /// to pick up icon + copy; fall back to a generic description for the
    /// aggregation / unknown cases.
    private var matchedType: AIProviderType? {
        AIProviderType.allCases.first { $0.displayName == providerUsed }
    }

    private var iconName: String {
        if let type = matchedType { return type.icon }
        switch providerUsed {
        case "Multiple": return "arrow.triangle.branch"
        case "Unknown":  return "questionmark.circle"
        default:         return "sparkles"
        }
    }

    private var tint: Color {
        guard let type = matchedType else { return .secondary }
        switch type {
        case .appleOnDevice:  return .blue
        case .embeddingLocal: return .teal
        case .openAI, .arceeAI, .openRouter: return .purple
        }
    }

    private var headline: String {
        if providerUsed == "Multiple" { return "Multiple sources" }
        if providerUsed == "Unknown"  { return "Extracted" }
        return providerUsed
    }

    private var tagline: String {
        guard let type = matchedType else {
            if providerUsed == "Multiple" {
                return "Different providers handled different files"
            }
            return "GagGrabber pulled these out of your file"
        }
        switch type {
        case .appleOnDevice:
            return "On-device • private • no network used"
        case .embeddingLocal:
            return "Offline segmenter • everything went to review"
        case .openAI, .arceeAI, .openRouter:
            return "Cloud AI • your file was sent to \(type.displayName)"
        }
    }
}

#Preview("Apple on-device") {
    ExtractionProviderBadge(providerUsed: "On-Device (Apple)")
        .padding()
}

#Preview("Embedding segmenter") {
    ExtractionProviderBadge(providerUsed: "On-Device (Offline Segmenter)")
        .padding()
}

#Preview("Cloud") {
    ExtractionProviderBadge(providerUsed: "OpenRouter")
        .padding()
}

#Preview("Multiple") {
    ExtractionProviderBadge(providerUsed: "Multiple")
        .padding()
}
