//
//  AISettingsView.swift
//  thebitbinder
//
//  Manages the Snack Vouchers GagGrabber uses to fuel its joke-extraction Gremlins.
//  User-facing copy intentionally contains no technical / provider names — the
//  underlying keys live in Keychain and nothing is sent to BitBinder servers.
//

import SwiftUI

struct AISettingsView: View {
    // House-blend voucher (free tier — keeps the Gremlins fed with no card on file)
    @State private var houseBlendKey = ""
    @State private var houseBlendConfigured = false
    @State private var showHouseBlendKey = false

    // Premium voucher (optional — faster / pickier Gremlins)
    @State private var premiumKey = ""
    @State private var premiumConfigured = false
    @State private var showPremiumKey = false

    @State private var savedProvider: AIProviderType? = nil
    @State private var showTutorial = false

    // Provider-order controls. Mirrors `AIJokeExtractionManager` UserDefaults
    // state; refreshed on appear and after every edit.
    @State private var providerOrder: [AIProviderType] = []
    @State private var disabledProviders: Set<AIProviderType> = []
    @State private var showAdvancedOrder: Bool = false

    var body: some View {
        List {
            // MARK: - Tutorial banner
            Section {
                Button {
                    showTutorial = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.bitbinderAccent.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundColor(Color.bitbinderAccent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Feed the Gremlins — 60 sec tour")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text("Not sure what any of this means? Start here.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            // MARK: - House Blend (free)
            Section {
                statusRow(configured: houseBlendConfigured)

                if houseBlendConfigured {
                    Button(role: .destructive) {
                        AIKeyLoader.clearKey(for: .openRouter)
                        AIKeyLoader.clearKey(for: .arceeAI)
                        houseBlendConfigured = false
                        houseBlendKey = ""
                    } label: {
                        Label("Return Voucher", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                } else {
                    keyField(
                        value: $houseBlendKey,
                        show: $showHouseBlendKey,
                        placeholder: "Paste your House Blend voucher",
                        onSave: {
                            let trimmed = houseBlendKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            AIKeyLoader.saveKey(trimmed, for: .openRouter)
                            AIKeyLoader.saveKey(trimmed, for: .arceeAI)
                            houseBlendConfigured = true
                            houseBlendKey = ""
                            showHouseBlendKey = false
                            savedProvider = .openRouter
                        }
                    )
                }

                if let signupURL = AIProviderType.openRouter.keySignupURL {
                    Link(destination: signupURL) {
                        Label("Grab a free House Blend voucher", systemImage: "leaf.fill")
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("House Blend (Free)")
            } footer: {
                Text("Keeps GagGrabber's Gremlins fed for text, PDFs, and photos — no card required.")
            }

            // MARK: - Premium Snack Voucher (optional)
            Section {
                statusRow(configured: premiumConfigured)

                if premiumConfigured {
                    Button(role: .destructive) {
                        AIKeyLoader.clearKey(for: .openAI)
                        premiumConfigured = false
                        premiumKey = ""
                    } label: {
                        Label("Return Voucher", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                } else {
                    keyField(
                        value: $premiumKey,
                        show: $showPremiumKey,
                        placeholder: "Paste your Premium Snack voucher",
                        onSave: {
                            let trimmed = premiumKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            AIKeyLoader.saveKey(trimmed, for: .openAI)
                            premiumConfigured = true
                            premiumKey = ""
                            showPremiumKey = false
                            savedProvider = .openAI
                        }
                    )
                }

                Button {
                    showTutorial = true
                } label: {
                    Label("Show me how (60 sec tour)", systemImage: "questionmark.bubble.fill")
                        .font(.subheadline)
                        .foregroundColor(Color.bitbinderAccent)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Premium Snack Voucher (Optional)")
            } footer: {
                Text("Feed the Gremlins premium snacks for sharper, pickier joke extraction. Costs pennies per use.")
            }

            // MARK: - Security note
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(Color.bitbinderAccent)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Locked in Your Keychain")
                            .font(.subheadline.weight(.semibold))
                        Text("Vouchers never touch BitBinder servers, never ride along to iCloud, and never show up in backups.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: - Advanced: Extraction order
            providerOrderSection
        }
        .navigationTitle("GagGrabber Fuel")
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
        .sheet(isPresented: $showTutorial) {
            GagGrabberFuelTutorialView()
                .onDisappear { refreshStatus() }
        }
    }

    // MARK: - Subviews

    private func statusRow(configured: Bool) -> some View {
        HStack {
            Text("Status")
                .foregroundStyle(.secondary)
            Spacer()
            if configured {
                Label("Gremlins fed", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
            } else {
                Label("Hungry", systemImage: "circle.dotted")
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

            Button("Feed 'Em") {
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
            Text("Gremlins are stuffed")
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

    // MARK: - Provider Order Section

    @ViewBuilder
    private var providerOrderSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAdvancedOrder) {
                Text("GagGrabber tries providers from top to bottom. Use the arrows to reorder and the toggle to disable any you never want to use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)

                ForEach(Array(providerOrder.enumerated()), id: \.element) { index, type in
                    providerRow(type: type, index: index)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Extraction Order")
                            .font(.subheadline.weight(.semibold))
                        Text("Advanced — control which providers GagGrabber tries and in what order.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            Text("On-device providers are free, private, and work offline but are typically less accurate than cloud AI. Move them up if you prefer offline-first — down if you want cloud quality first.")
                .font(.caption)
        }
    }

    private func providerRow(type: AIProviderType, index: Int) -> some View {
        let isConfigured = AIJokeExtractionManager.shared.isProviderReady(type)
        let isEnabled = !disabledProviders.contains(type)
        let isFirst = index == 0
        let isLast  = index == providerOrder.count - 1

        return HStack(spacing: 10) {
            Image(systemName: type.icon)
                .font(.subheadline)
                .foregroundStyle(tint(for: type))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(type.displayName)
                    .font(.subheadline.weight(.medium))
                Text(statusText(type: type, configured: isConfigured, enabled: isEnabled))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 0) {
                Button {
                    moveProvider(type, direction: -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(isFirst)
                .opacity(isFirst ? 0.3 : 1)

                Button {
                    moveProvider(type, direction: 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(isLast)
                .opacity(isLast ? 0.3 : 1)
            }

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { setEnabled($0, for: type) }
            ))
            .labelsHidden()
            .tint(Color.bitbinderAccent)
        }
        .padding(.vertical, 4)
    }

    private func tint(for type: AIProviderType) -> Color {
        switch type {
        case .appleOnDevice:  return .blue
        case .embeddingLocal: return .teal
        case .openAI, .arceeAI, .openRouter: return .purple
        }
    }

    private func statusText(type: AIProviderType, configured: Bool, enabled: Bool) -> String {
        if !enabled { return "Disabled" }
        if configured { return "Ready" }
        switch type {
        case .appleOnDevice:  return "Unavailable on this device"
        case .embeddingLocal: return "Unavailable"
        case .openAI:         return "No Premium voucher"
        case .arceeAI, .openRouter: return "No House Blend voucher"
        }
    }

    private func moveProvider(_ type: AIProviderType, direction: Int) {
        guard let currentIndex = providerOrder.firstIndex(of: type) else { return }
        let targetIndex = currentIndex + direction
        guard providerOrder.indices.contains(targetIndex) else { return }

        var order = providerOrder
        order.swapAt(currentIndex, targetIndex)
        providerOrder = order
        AIJokeExtractionManager.shared.providerOrder = order
        haptic(.light)
    }

    private func setEnabled(_ enabled: Bool, for type: AIProviderType) {
        AIJokeExtractionManager.shared.setProvider(type, enabled: enabled)
        if enabled {
            disabledProviders.remove(type)
        } else {
            disabledProviders.insert(type)
        }
    }

    // MARK: - Helpers

    private func refreshStatus() {
        houseBlendConfigured = AIKeyLoader.loadKey(for: .openRouter) != nil
        premiumConfigured    = AIKeyLoader.loadKey(for: .openAI) != nil
        providerOrder        = AIJokeExtractionManager.shared.providerOrder
        disabledProviders    = AIJokeExtractionManager.shared.disabledProviders
    }
}

#Preview {
    NavigationStack {
        AISettingsView()
    }
}
