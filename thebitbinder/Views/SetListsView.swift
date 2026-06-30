//
//  SetListsView.swift
//  thebitbinder
//
//  Set lists view using standard iOS patterns.
//

import SwiftUI
import SwiftData

struct SetListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<SetList> { !$0.isTrashed }) private var setLists: [SetList]
    @Query private var allJokes: [Joke]
    @Query private var allRoastJokes: [RoastJoke]
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @State private var showingCreateSetList = false
    @State private var showingTrash = false
    @State private var showingRecording = false
    @State private var searchText = ""
    @State private var persistenceError: String?
    @State private var showingPersistenceError = false
    
    var filteredSetLists: [SetList] {
        let sorted = setLists.sorted { $0.dateModified > $1.dateModified }
        if searchText.isEmpty {
            return sorted
        }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        Group {
            if filteredSetLists.isEmpty && searchText.isEmpty {
                BitBinderEmptyState(
                    icon: "list.bullet.rectangle.portrait",
                    title: "No Sets Yet",
                    subtitle: "Create a set to organize jokes, notes, and run-through recordings.",
                    actionTitle: "Create Set",
                    action: { showingCreateSetList = true },
                    roastMode: roastMode
                )
            } else {
                List {
                    ForEach(filteredSetLists) { setList in
                        NavigationLink(destination: SetListDetailView(setList: setList)) {
                            SetListRowView(setList: setList)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                softDeleteSetList(setList)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteSetLists)
                }
                .listStyle(.insetGrouped)
                .readableWidth()
                .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            }
        }
        .searchable(text: $searchText, prompt: "Search sets")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingCreateSetList = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create set list")
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingRecording = true
                    } label: {
                        Label("Record Set", systemImage: "record.circle")
                    }
                    
                    Section {
                        Button {
                            showingTrash = true
                        } label: {
                            Label("Trash", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Set list options")
            }
        }
        .navigationDestination(isPresented: $showingTrash) {
            SetListTrashView()
        }
        .sheet(isPresented: $showingCreateSetList) {
            CreateSetListView()
        }
        .sheet(isPresented: $showingRecording) {
            StandaloneRecordingView()
        }
        .alert("Error", isPresented: $showingPersistenceError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
        .task {
            cleanAllDanglingIDs()
        }
    }
    
    private func deleteSetLists(at offsets: IndexSet) {
        let snapshot = filteredSetLists
        for index in offsets {
            guard index < snapshot.count else { continue }
            snapshot[index].moveToTrash()
        }
        do {
            try modelContext.save()
        } catch {
            print("[SetListsView] Failed to save after soft-delete: \(error)")
            persistenceError = "Could not delete set list: \(error.localizedDescription)"
            showingPersistenceError = true
        }
    }
    
    private func cleanAllDanglingIDs() {
        let jokeIDSet = Set(allJokes.map(\.id))
        let roastIDSet = Set(allRoastJokes.map(\.id))
        var changed = false
        for setList in setLists {
            if setList.cleanDanglingIDs(existingJokeIDs: jokeIDSet, existingRoastJokeIDs: roastIDSet) {
                changed = true
            }
        }
        if changed {
            try? modelContext.save()
        }
    }

    private func softDeleteSetList(_ setList: SetList) {
        setList.moveToTrash()
        do {
            try modelContext.save()
        } catch {
            // IMPORTANT: Do NOT restore on save failure - this causes "undeleted" items
            // to reappear unexpectedly. Instead, the delete stays in memory and will
            // be retried on next save. User sees the error and item stays visually deleted.
            print("[SetListsView] Failed to save after soft-delete: \(error)")
            persistenceError = "Delete may not have saved. Please try again or check your connection."
            showingPersistenceError = true
        }
    }
}

struct SetListRowView: View {
    let setList: SetList
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    private var jokeCount: Int {
        roastMode ? setList.roastJokeIDs.count : setList.jokeIDs.count
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(setList.name)
                        .font(.body)
                        .foregroundColor(.primary)
                }

                HStack(spacing: 8) {
                    Text("\(jokeCount) \(roastMode ? "roasts" : "jokes")")
                    if setList.estimatedMinutes > 0 {
                        Text("•")
                        Text("\(setList.estimatedMinutes) min")
                    }
                    if !setList.venueName.isEmpty {
                        Text("•")
                        Text(setList.venueName)
                    }
                }
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(setList.dateModified.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption)
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        SetListsView()
            .navigationTitle("Sets")
    }
    .modelContainer(for: SetList.self, inMemory: true)
}
