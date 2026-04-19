//
//  MoveJokeToFolderSheet.swift
//  thebitbinder
//
//  Move a joke to a different folder via long-press context menu or batch action.
//

import SwiftUI
import SwiftData

struct MoveJokeToFolderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let joke: Joke
    let allFolders: [JokeFolder]
    
    @State private var showingCreateFolder = false
    @State private var newFolderName = ""
    @State private var saveError: String?
    @State private var showingSaveError = false
    
    private var currentFolderIDs: Set<UUID> {
        Set((joke.folders ?? []).map(\.id))
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Remove from all folders
                Section {
                    Button {
                        joke.folders = []
                        joke.dateModified = Date()
                        saveAndDismiss()
                    } label: {
                        HStack {
                            Image(systemName: "tray.full")
                                .foregroundColor(.secondary)
                            Text("Unfiled (All Jokes)")
                                .foregroundColor(.primary)
                            Spacer()
                            if currentFolderIDs.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color.bitbinderAccent)
                            }
                        }
                    }
                }
                
                // Existing folders
                Section("Folders") {
                    ForEach(allFolders) { folder in
                        Button {
                            moveJoke(to: folder)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(Color.bitbinderAccent)
                                Text(folder.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if currentFolderIDs.contains(folder.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color.bitbinderAccent)
                                }
                            }
                        }
                    }
                    
                    // Create new folder inline
                    Button {
                        showingCreateFolder = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.green)
                            Text("New Folder...")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("New Folder", isPresented: $showingCreateFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Create") {
                    createFolderAndMove()
                }
                Button("Cancel", role: .cancel) {
                    newFolderName = ""
                }
            } message: {
                Text("Enter a name for the new folder.")
            }
            .alert("Error", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "An unknown error occurred")
            }
        }
    }
    
    private func moveJoke(to folder: JokeFolder) {
        var currentFolders = joke.folders ?? []
        
        if currentFolders.contains(where: { $0.id == folder.id }) {
            // Already in this folder — remove it (toggle behavior)
            currentFolders.removeAll(where: { $0.id == folder.id })
        } else {
            // Add to folder
            currentFolders.append(folder)
        }
        
        joke.folders = currentFolders
        joke.dateModified = Date()
        saveAndDismiss()
    }
    
    private func createFolderAndMove() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            newFolderName = ""
            return
        }
        
        let newFolder = JokeFolder(name: trimmed)
        modelContext.insert(newFolder)
        
        var currentFolders = joke.folders ?? []
        currentFolders.append(newFolder)
        joke.folders = currentFolders
        joke.dateModified = Date()
        
        newFolderName = ""
        saveAndDismiss()
    }
    
    private func saveAndDismiss() {
        do {
            try modelContext.save()
            haptic(.light)
            dismiss()
        } catch {
            print(" [MoveJokeToFolderSheet] Failed to save: \(error)")
            saveError = "Could not move joke: \(error.localizedDescription)"
            showingSaveError = true
        }
    }
}
