// AddRoastJokeView.swift
//  thebitbinder
//
//  Quick-add sheet for new roast jokes with rapid-fire mode.
//

import SwiftUI
import SwiftData

struct AddRoastJokeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let target: RoastTarget

    @State private var content = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var keepAdding = false
    @State private var savedCount = 0
    @State private var showSavedFeedback = false
    @FocusState private var isTextFocused: Bool

    private var accentColor: Color { FirePalette.core }
    
    /// Safe property accessors to prevent crashes on invalidated models
    private var safeName: String { target.isValid ? target.name : "Target" }
    private var safePhotoData: Data? { target.isValid ? target.photoData : nil }
    
    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Target header - compact
                HStack(spacing: 10) {
                    AsyncAvatarView(
                        photoData: safePhotoData,
                        size: 36,
                        fallbackInitial: String(safeName.prefix(1).uppercased()),
                        accentColor: accentColor
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Roasting")
                            .font(.caption2)
                            .foregroundColor(FirePalette.sub)
                        Text(safeName)
                            .font(.subheadline.bold())
                            .foregroundColor(FirePalette.text)
                    }
                    Spacer()

                    if savedCount > 0 {
                        Text("\(savedCount) added")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(FirePalette.emberCTA)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(FirePalette.card)
                .overlay(
                    Rectangle()
                        .fill(FirePalette.edge)
                        .frame(height: 0.5),
                    alignment: .bottom
                )

                // Main text area - big and focused
                ZStack(alignment: .topLeading) {
                    if content.isEmpty {
                        Text("Write your roast...")
                            .foregroundColor(FirePalette.sub)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                    }

                    TextEditor(text: $content)
                        .focused($isTextFocused)
                        .scrollContentBackground(.hidden)
                        .foregroundColor(FirePalette.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .frame(maxHeight: .infinity)
                .background(FirePalette.bg)

                // Bottom controls
                VStack(spacing: 12) {
                    // Keep adding toggle
                    HStack {
                        Toggle(isOn: $keepAdding) {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption)
                                    .foregroundColor(keepAdding ? accentColor : FirePalette.sub)
                                Text("Rapid Fire Mode")
                                    .font(.subheadline)
                                    .foregroundColor(FirePalette.text)
                            }
                        }
                        .tint(accentColor)
                    }
                    .padding(.horizontal, 16)

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.06))
                                .foregroundColor(FirePalette.text)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(FirePalette.edge, lineWidth: 0.5)
                                )
                        }

                        Button {
                            saveRoast()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: keepAdding ? "plus" : "checkmark")
                                    .font(.subheadline.bold())
                                Text(keepAdding ? "Add & Next" : "Save")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSave
                                ? AnyShapeStyle(FirePalette.emberCTA)
                                : AnyShapeStyle(Color.white.opacity(0.08)))
                            .foregroundColor(canSave ? .white : FirePalette.sub)
                            .cornerRadius(12)
                        }
                        .disabled(!canSave)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)
                .background(FirePalette.card)
                .overlay(
                    Rectangle()
                        .fill(FirePalette.edge)
                        .frame(height: 0.5),
                    alignment: .top
                )
            }
            .background(FirePalette.bg.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(FirePalette.sub)
                    }
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button {
                            saveRoast()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: keepAdding ? "plus" : "checkmark")
                                Text(keepAdding ? "Add & Next" : "Save")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(canSave ? accentColor : .secondary)
                        }
                        .disabled(!canSave)
                    }
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard scenePhase == .active else { return }
                    isTextFocused = true
                }
            }
        }
    }

    private func saveRoast() {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }
        
        // Safety check - ensure target is still valid
        guard target.isValid else {
            saveErrorMessage = "Target was deleted. Cannot save roast."
            showSaveError = true
            return
        }

        let joke = RoastJoke(
            content: trimmedContent,
            target: target
        )
        modelContext.insert(joke)
        target.dateModified = Date()
        
        do {
            try modelContext.save()
            savedCount += 1
            
            #if DEBUG
            print(" [AddRoastJokeView] Roast saved for '\(safeName)' (id: \(joke.id))")
            #endif
            
            if keepAdding {
                // Clear for next roast
                withAnimation(.easeOut(duration: 0.15)) {
                    content = ""
                    showSavedFeedback = true
                }
                haptic(.light)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    showSavedFeedback = false
                }
            } else {
                dismiss()
            }
        } catch {
            #if DEBUG
            print(" [AddRoastJokeView] Failed to save: \(error)")
            #endif
            saveErrorMessage = "Could not save roast: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
