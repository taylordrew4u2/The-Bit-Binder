//
//  GagGrabberFuelTutorialView.swift
//  thebitbinder
//
//  A playful, step-by-step walkthrough for pasting in a premium Snack Voucher.
//  Intentionally avoids all technical / provider terminology in user-facing text —
//  everything is framed as feeding GagGrabber's tiny joke-sniffing Gremlins.
//

import SwiftUI

struct GagGrabberFuelTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var currentStep = 0
    @State private var voucher = ""
    @State private var showVoucher = false
    @State private var saveAttempted = false
    @State private var saved = false

    // The "Snack Counter" — kept as an implementation detail; user never sees this string.
    private let snackCounterURL = URL(string: "https://platform.openai.com/api-keys")!

    private let stepCount = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressDots
                    .padding(.top, 16)

                TabView(selection: $currentStep) {
                    meetGremlinsPage.tag(0)
                    snackCounterPage.tag(1)
                    grabVoucherPage.tag(2)
                    feedPage.tag(3)
                    donePage.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)

                footerButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            .navigationTitle("Feed the Gremlins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saved ? "Done" : "Close") { dismiss() }
                        .font(.subheadline.weight(.medium))
                }
            }
            .interactiveDismissDisabled(currentStep == 3 && !voucher.isEmpty && !saved)
        }
    }

    // MARK: - Progress

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index == currentStep ? Color.bitbinderAccent : Color.secondary.opacity(0.3))
                    .frame(width: index == currentStep ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentStep)
            }
        }
    }

    // MARK: - Pages

    private var meetGremlinsPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)

                heroIcon("sparkles", background: Color.yellow.opacity(0.18), tint: .orange)

                Text("Meet the Gremlins")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                VStack(spacing: 14) {
                    Text("GagGrabber runs on a tiny crew of joke-sniffing Gremlins that live inside your phone.")
                    Text("Right now they're on the house blend — free and already working. If you want them **fast, picky, and punchline-obsessed**, feed them a Premium Snack Voucher.")
                    Text("It'll take about 60 seconds. Ready?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color.bitbinderAccent)
                }
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 28)

                Spacer(minLength: 40)
            }
        }
    }

    private var snackCounterPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                heroIcon("storefront.fill", background: Color.bitbinderAccent.opacity(0.15), tint: Color.bitbinderAccent)

                Text("Step 1 — Visit the Snack Counter")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Tap the big button. You'll pop over to the Snack Counter in Safari.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    haptic(.light)
                    openURL(snackCounterURL)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "safari.fill")
                        Text("Open the Snack Counter")
                            .font(.body.weight(.semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(Color.bitbinderAccent)
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    heads_up(text: "They'll ask you to sign up or log in. Normal website stuff.")
                    heads_up(text: "You'll drop a card on file so they can bill you. It's usually pennies per use — seriously.")
                    heads_up(text: "When you've got your voucher copied, swing back here for Step 2.")
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 32)
            }
        }
    }

    private var grabVoucherPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                heroIcon("doc.badge.plus", background: Color.purple.opacity(0.15), tint: .purple)

                Text("Step 2 — Grab Your Voucher")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 16) {
                    instructionRow(number: 1, text: "Tap **Create new secret key** on the Snack Counter.")
                    instructionRow(number: 2, text: "Name it anything — **Joke Gremlin Snacks** has a nice ring to it.")
                    instructionRow(number: 3, text: "Tap the little **copy** button next to the voucher. Your phone just stashed it on the clipboard.")
                }
                .padding(.horizontal, 24)

                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("The voucher only shows up **once**. If you lose it, just generate a new one.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                )
                .padding(.horizontal, 24)

                Spacer(minLength: 32)
            }
        }
    }

    private var feedPage: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 20)

                heroIcon("fork.knife", background: Color.green.opacity(0.15), tint: .green)

                Text("Step 3 — Feed 'Em")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Paste your voucher below. The Gremlins will do the rest.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Paste field
                VStack(spacing: 10) {
                    HStack {
                        Group {
                            if showVoucher {
                                TextField("sk-…", text: $voucher)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("sk-…", text: $voucher)
                            }
                        }
                        .font(.system(.body, design: .monospaced))

                        Button {
                            showVoucher.toggle()
                        } label: {
                            Image(systemName: showVoucher ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)

                        if voucher.isEmpty {
                            Button {
                                pasteFromClipboard()
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                                    .foregroundColor(Color.bitbinderAccent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.secondarySystemBackground))
                    )

                    Button {
                        feedGremlins()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: saved ? "checkmark.circle.fill" : "fork.knife")
                            Text(saved ? "Munched!" : "Feed 'Em")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(saved ? Color.green : Color.bitbinderAccent)
                        )
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(voucher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saved)
                }
                .padding(.horizontal, 24)

                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(Color.bitbinderAccent)
                    Text("Locked in your Keychain. Never leaves this phone, never touches our servers, never rides along to iCloud backups.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .padding(.horizontal, 24)

                Spacer(minLength: 32)
            }
        }
    }

    private var donePage: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 60)

                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 120, height: 120)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 72))
                        .foregroundColor(.green)
                }

                Text("The Gremlins Are Stuffed")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("They're awake, caffeinated, and ready to rip jokes out of anything you throw at them — text, photos, PDFs, scribbled napkins, the works.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("You can swing back any time to top them up.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            if currentStep > 0 && !saved {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline.weight(.medium))
                }
            } else {
                Spacer().frame(width: 80)
            }

            Spacer()

            if currentStep < stepCount - 1 {
                Button {
                    withAnimation { currentStep += 1 }
                } label: {
                    HStack(spacing: 4) {
                        Text(nextButtonLabel)
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.bitbinderAccent)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .disabled(currentStep == 3 && !saved)
                .opacity(currentStep == 3 && !saved ? 0.4 : 1.0)
            } else {
                Button {
                    dismiss()
                } label: {
                    Text("All Done")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.bitbinderAccent)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var nextButtonLabel: String {
        switch currentStep {
        case 0: return "Let's Do It"
        case 1: return "I've Got One"
        case 2: return "Got It Copied"
        default: return "Next"
        }
    }

    // MARK: - Sub-components

    private func heroIcon(_ symbol: String, background: Color, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(background)
                .frame(width: 100, height: 100)
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundColor(tint)
        }
    }

    private func heads_up(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundColor(Color.bitbinderAccent)
                .padding(.top, 4)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.bitbinderAccent.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(Color.bitbinderAccent)
            }
            Text(.init(text))
                .font(.body)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func pasteFromClipboard() {
        if let pasted = UIPasteboard.general.string {
            voucher = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            haptic(.selection)
        }
    }

    private func feedGremlins() {
        let trimmed = voucher.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        AIKeyLoader.saveKey(trimmed, for: .openAI)
        saved = true
        voucher = ""
        showVoucher = false
        haptic(.success)
        // Auto-advance to the celebration page
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation {
                currentStep = stepCount - 1
            }
        }
    }
}

#Preview {
    GagGrabberFuelTutorialView()
}
