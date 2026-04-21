//
//  ExtractionHintsPreflightSheet.swift
//  thebitbinder
//
//  Sheet presented between file selection and the AI extraction pipeline.
//  Lets the user answer a few structural questions about their document so
//  GagGrabber can split jokes more accurately, or skip entirely with
//  "Just figure it out".
//

import SwiftUI

struct ExtractionHintsPreflightSheet: View {
    let fileNameSummary: String
    let onContinue: (ExtractionHints) -> Void
    let onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hints: ExtractionHints = .unspecified

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    ExtractionHintsForm(hints: $hints)

                    actionButtons
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .navigationTitle("Before we grab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(fileNameSummary, systemImage: "doc.text")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text("Answer a few quick questions so GagGrabber splits your jokes cleanly — or skip it and let GagGrabber figure it out.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                onContinue(hints)
                dismiss()
            } label: {
                Text("Use these hints")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                onSkip()
                dismiss()
            } label: {
                Text("Just figure it out")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}
