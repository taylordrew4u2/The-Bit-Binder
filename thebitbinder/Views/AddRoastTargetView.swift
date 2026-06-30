//
//  AddRoastTargetView.swift
//  thebitbinder
//
//  Sheet to create a new person to roast.
//

import SwiftUI
import SwiftData
import PhotosUI

struct AddRoastTargetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var notes = ""
    @State private var traits: [String] = [""]
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoImage: UIImage?

    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @FocusState private var focusedField: Field?

    private var accentColor: Color { FirePalette.core }

    private enum Field: Hashable {
        case name
        case notes
        case detail(Int)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Photo section
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            if let photoImage {
                                Image(uiImage: photoImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(accentColor, lineWidth: 3))
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(accentColor.opacity(0.12))
                                        .frame(width: 100, height: 100)
                                    VStack(spacing: 4) {
                                        Image(systemName: "person.crop.circle.badge.plus")
                                            .font(.system(size: 32))
                                            .foregroundColor(accentColor)
                                        Text("Add Photo")
                                            .font(.caption2)
                                            .foregroundColor(accentColor)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityLabel(photoImage == nil ? "Add target photo" : "Change target photo")
                }

                Section("Who are you roasting?") {
                    TextField("Name", text: $name)
                        .font(.headline)
                        .roastRowBackground()
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .notes }
                }

                Section("Notes (optional)") {
                    TextField("e.g. friend, coworker, celebrity...", text: $notes)
                        .roastRowBackground()
                        .focused($focusedField, equals: .notes)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .detail(0) }
                }

                Section {
                    ForEach(Array(traits.enumerated()), id: \.offset) { index, _ in
                        if index < traits.count {
                            HStack {
                                TextField("e.g. works in finance, always late...", text: Binding(
                                    get: { index < traits.count ? traits[index] : "" },
                                    set: { newValue in
                                        if index < traits.count {
                                            traits[index] = newValue
                                        }
                                    }
                                ))
                                .focused($focusedField, equals: .detail(index))
                                .submitLabel(.done)
                                if traits.count > 1 {
                                    Button {
                                        if index < traits.count {
                                            traits.remove(at: index)
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .roastRowBackground()
                        }
                    }
                    Button {
                        traits.append("")
                    } label: {
                        Label("Add another", systemImage: "plus.circle")
                            .foregroundColor(accentColor)
                    }
                    .roastRowBackground()
                } header: {
                    Text("What do you know about them?")
                } footer: {
                    Text("Bullet points about the target — habits, quirks, job, looks, anything roastable.")
                }
            }
            .roastFormTheme()
            .navigationTitle("New Target")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(accentColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        saveTarget()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task(id: selectedPhoto) {
                await loadSelectedPhoto()
            }
            .onAppear {
                focusedField = .name
                #if DEBUG
                print(" [AddRoastTargetView] View appeared")
                print(" [AddRoastTargetView] ModelContext available: \(modelContext)")
                #endif
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func saveTarget() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let cleanTraits = traits
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let target = RoastTarget(
            name: trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            traits: cleanTraits,
            photoData: photoData
        )
        
        modelContext.insert(target)
        
        do {
            try modelContext.save()
            #if DEBUG
            print(" [AddRoastTargetView] Target '\(trimmed)' saved successfully (id: \(target.id))")
            #endif
            dismiss()
        } catch {
            #if DEBUG
            print(" [AddRoastTargetView] Failed to save: \(error)")
            #endif
            saveErrorMessage = "Could not save target: \(error.localizedDescription)"
            showSaveError = true
        }
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        guard let data = try? await selectedPhoto.loadTransferable(type: Data.self),
              !Task.isCancelled,
              let original = UIImage(data: data) else {
            return
        }

        let scaled = RoastTargetPhotoHelper.downscale(original, maxLongEdge: 800)
        let scaledData = scaled.jpegData(compressionQuality: 0.8)

        await MainActor.run {
            guard photoData != scaledData else {
                self.selectedPhoto = nil
                return
            }
            photoData = scaledData
            photoImage = scaled
            self.selectedPhoto = nil
        }
    }
}
