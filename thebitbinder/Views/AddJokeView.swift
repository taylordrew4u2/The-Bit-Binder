//
//  AddJokeView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData

struct AddJokeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var folders: [JokeFolder]
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @State private var title = ""
    @State private var content = ""
    @State private var autoAssign = UserDefaults.standard.bool(forKey: "autoOrganizeEnabled")
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    var selectedFolder: JokeFolder?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Title")) {
                    TextField("Enter joke title", text: $title)
                }
                
                Section(header: Text("Content")) {
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                }
                
                if let folder = selectedFolder {
                    Section {
                        HStack {
                            Label("Folder", systemImage: "folder")
                            Spacer()
                            Text(folder.name)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .scrollContentBackground(roastMode ? .hidden : .visible)
            .background(roastMode ? AppTheme.Colors.roastBackground : Color.clear)
            .navigationTitle("New Joke")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: roastMode)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveJoke()
                    }
                    .disabled(content.isEmpty)
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                }
            }
        }
        .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
    
    private func saveJoke() {
        let joke = Joke(content: content, title: title, folder: selectedFolder)
        modelContext.insert(joke)
        
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .jokeDatabaseDidChange, object: nil)
            dismiss()
        } catch {
            print("❌ [AddJokeView] Failed to save joke: \(error)")
            saveErrorMessage = "Could not save joke: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
