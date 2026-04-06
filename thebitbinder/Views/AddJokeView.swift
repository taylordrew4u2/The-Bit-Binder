//
//  AddJokeView.swift
//  thebitbinder
//
//  Standard iOS sheet for adding a new joke.
//

import SwiftUI
import SwiftData

struct AddJokeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<JokeFolder> { !$0.isDeleted }) private var folders: [JokeFolder]
    
    @State private var title = ""
    @State private var content = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var isSaving = false
    @FocusState private var contentFocused: Bool
    
    var selectedFolder: JokeFolder?
    
    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Title Section
                Section {
                    TextField("Title (optional)", text: $title)
                } header: {
                    Text("Title")
                }
                
                // Content Section
                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                        .focused($contentFocused)
                } header: {
                    HStack {
                        Text("Joke")
                        Spacer()
                        if !content.isEmpty {
                            Text("\(content.split(separator: " ").count) words")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Folder indicator
                if let folder = selectedFolder {
                    Section {
                        Label(folder.name, systemImage: "folder.fill")
                            .foregroundColor(.secondary)
                    } header: {
                        Text("Folder")
                    }
                }
            }
            .navigationTitle("New Joke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveJoke()
                    }
                    .disabled(!canSave || isSaving)
                    .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            contentFocused = false
                        }
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    contentFocused = true
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
    }
    
    private func saveJoke() {
        isSaving = true
        haptic(.light)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let joke = Joke(content: content, title: title, folder: selectedFolder)
            modelContext.insert(joke)
            
            do {
                try modelContext.save()
                haptic(.success)
                NotificationCenter.default.post(name: .jokeDatabaseDidChange, object: nil)
                dismiss()
            } catch {
                isSaving = false
                haptic(.error)
                print("[AddJokeView] Failed to save joke: \(error)")
                saveErrorMessage = "Could not save joke: \(error.localizedDescription)"
                showSaveError = true
            }
        }
    }
}

#Preview {
    AddJokeView()
        .modelContainer(for: [Joke.self, JokeFolder.self], inMemory: true)
}