//
//  CreateSetListView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData

struct CreateSetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @State private var name = ""
    @State private var notes = ""
    @State private var estimatedMinutes = 5
    @State private var venueName = ""
    @State private var includeDate = false
    @State private var setDate = Date()
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case venue
        case notes
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(roastMode ? "Roast set name" : "Set name", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .venue
                        }

                    TextField("Venue or room", text: $venueName)
                        .focused($focusedField, equals: .venue)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .notes
                        }
                } header: {
                    Text("Set Details")
                } footer: {
                    if trimmedName.isEmpty {
                        Text("Name the set before creating it.")
                    }
                }

                Section("Timing") {
                    Stepper(value: $estimatedMinutes, in: 1...180) {
                        LabeledContent("Target length", value: "\(estimatedMinutes) min")
                    }

                    Toggle("Add date", isOn: $includeDate.animation())

                    if includeDate {
                        DatePicker("Date", selection: $setDate)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .notes)
                }
            }
            .navigationTitle("New Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSetList()
                    }
                    .disabled(trimmedName.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(Color.bitbinderAccent)
        .onAppear {
            focusedField = .name
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
    
    private func createSetList() {
        let setList = SetList(
            name: trimmedName,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        setList.estimatedMinutes = estimatedMinutes
        setList.venueName = venueName.trimmingCharacters(in: .whitespacesAndNewlines)
        setList.performanceDate = includeDate ? setDate : nil

        modelContext.insert(setList)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print(" [CreateSetListView] Failed to save set list: \(error)")
            saveErrorMessage = "Could not create set list: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
