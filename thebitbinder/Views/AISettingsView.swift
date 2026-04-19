//
//  AISettingsView.swift
//  thebitbinder
//
//  Manage API keys for GagGrabber AI extraction providers.
//  Keys are stored in Keychain — never persisted to disk or iCloud.
//

import SwiftUI

struct AISettingsView: View {
    // OpenRouter key (covers both OpenRouter and Arcee AI providers)
    @State private var openRouterKey = ""
    @State private var openRouterConfigured = false
    @State private var showOpenRouterKey = false

    // OpenAI key (optional)
    @State private var openAIKey = ""
    @State private var openAIConfigured = false
    @State private var showOpenAIKey = false

    @State private var savedProvider: AIProviderType? = nil

    var body: some View {
        List {
            // MARK: - OpenRouter (powers GagGrabber)
            Section {
                statusRow(configured: openRouterConfigured, providerName: "OpenRouter")

                if openRouterConfigured {
                    Button(role: .destructive) {
                        AIKeyLoader.clearKey(for: .openRouter)
                        AIKeyLoader.clearKey(for: .arceeAI)
                        openRouterConfigured = false
                        openRouterKey = ""
                    } label: {
                        Label("Remove Key", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                } else {
                    keyField(
                        value: $openRouterKey,
                        show: $showOpenRouterKey,
                        placeholder: "sk-or-v1-…",
                        onSave: {
                            let trimmed = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            AIKeyLoader.saveKey(trimmed, for: .openRouter)
                            AIKeyLoader.saveKey(trimmed, for: .arceeAI)
                            openRouterConfigured = true
                            openRouterKey = ""
                            showOpenRouterKey = false
                            savedProvider = .openRouter
                        }
                    )
                }

                Link(destination: AIProviderType.openRouter.keySignupURL) {
                    Label("Get a free key at openrouter.ai", systemImage: "key.radiowaves.forward")
                        .font(.subheadline)
                }
            } header: {
                Text("GagGrabber AI (OpenRouter)")
            } footer: {
                Text("Powers joke extraction from text, PDFs, and photos. Free models available — no credit card required.")
            }

            // MARK: - OpenAI (optional)
            Section {
                statusRow(configured: openAIConfigured, providerName: "OpenAI")

                if openAIConfigured {
                    Button(role: .destructive) {
                        AIKeyLoader.clearKey(for: .openAI)
                        openAIConfigured = false
                        openAIKey = ""
                    } label: {
                        Label("Remove Key", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                } else {
                    keyField(
                        value: $openAIKey,
                        show: $showOpenAIKey,
                        placeholder: "sk-…",
                        onSave: {
                            let trimmed = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            AIKeyLoader.saveKey(trimmed, for: .openAI)
                            openAIConfigured = true
                            openAIKey = ""
                            showOpenAIKey = false
                            savedProvider = .openAI
                        }
                    )
                }

                Link(destination: AIProviderType.openAI.keySignupURL) {
                    Label("Get a key at platform.openai.com", systemImage: "key.radiowaves.forward")
                        .font(.subheadline)
                }
            } header: {
                Text("OpenAI (Optional)")
            } footer: {
                Text("Enables GPT-4 extraction for higher accuracy. OpenRouter covers most use cases without this.")
            }

            // MARK: - Security note
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(Color.bitbinderAccent)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Stored Securely in Keychain")
                            .font(.subheadline.weight(.semibold))
                        Text("Keys are never sent to BitBinder servers, stored in iCloud, or included in backups.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("AI Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshStatus() }
        .overlay(alignment: .bottom) {
            if savedProvider != nil {
                savedToast
            }
        }
        .onChange(of: savedProvider) { _, new in
            guard new != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                savedProvider = nil
            }
        }
    }

    // MARK: - Subviews

    private func statusRow(configured: Bool, providerName: String) -> some View {
        HStack {
            Text("Status")
                .foregroundStyle(.secondary)
            Spacer()
            if configured {
                Label("Configured", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
            } else {
                Label("Not configured", systemImage: "xmark.circle")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
    }

    private func keyField(
        value: Binding<String>,
        show: Binding<Bool>,
        placeholder: String,
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Group {
                    if show.wrappedValue {
                        TextField(placeholder, text: value)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField(placeholder, text: value)
                    }
                }
                .font(.system(.body, design: .monospaced))

                Button {
                    show.wrappedValue.toggle()
                } label: {
                    Image(systemName: show.wrappedValue ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button("Save Key") {
                onSave()
                haptic(.success)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.bitbinderAccent)
            .disabled(value.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(maxWidth: .infinity)
        }
    }

    private var savedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color.bitbinderAccent)
            Text("Key saved to Keychain")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        )
        .padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(EffortlessAnimation.smooth, value: savedProvider != nil)
    }

    // MARK: - Helpers

    private func refreshStatus() {
        openRouterConfigured = AIKeyLoader.loadKey(for: .openRouter) != nil
        openAIConfigured     = AIKeyLoader.loadKey(for: .openAI) != nil
    }
}

#Preview {
    NavigationStack {
        AISettingsView()
    }
}
