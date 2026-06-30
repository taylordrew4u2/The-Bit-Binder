//
//  JokeComponents.swift
//  thebitbinder
//
//  Joke-related UI components using native iOS design patterns.
//

import SwiftUI
import SwiftData

// MARK: - Joke Card View (Grid)

struct JokeCardView: View {
    let joke: Joke
    var scale: CGFloat = 1.0
    var roastMode: Bool = false
    var showFullContent: Bool = true
    
    private var isHit: Bool { joke.isHit }
    private var isOpenMic: Bool { joke.isOpenMic }

    /// Title fallback chain: explicit title → keyword-generated → first line
    /// of content trimmed to ~60 chars → "Untitled". Without the last two
    /// rungs, content that is all stop-words renders as a blank square.
    private var resolvedTitle: String {
        let explicit = joke.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        let generated = KeywordTitleGenerator.displayTitle(from: joke.content)
        if !generated.isEmpty { return generated }
        let firstLine = joke.content
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !firstLine.isEmpty {
            return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
        }
        return "Untitled"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Hit / Open Mic accent strip
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isHit ? Color.bitbinderAccent : (isOpenMic ? Color.bitbinderAccent : .clear))
                .frame(width: 4)
                .padding(.vertical, 10)
            
            VStack(alignment: .leading, spacing: 10) {
                // Header: Title + Hit / Open Mic indicator
                HStack(alignment: .top, spacing: 8) {
                    Text(resolvedTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Spacer(minLength: 4)
                    
                    HStack(spacing: 4) {
                        if isOpenMic {
                            JokeStatusGlyph(icon: "mic.fill", accessibilityLabel: "Open Mic")
                        }

                        if isHit {
                            JokeStatusGlyph(icon: "star.fill", accessibilityLabel: "Hit")
                        }
                    }
                }
                
                // Content preview
                if showFullContent {
                    Text(joke.content)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                        .lineSpacing(2)
                }
                
                Spacer(minLength: 0)
                
                // Footer: Date + folder indicator
                HStack(spacing: 6) {
                    Text(joke.dateModified.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                    
                    Spacer()
                    
                    if let folders = joke.folders, !folders.isEmpty {
                        Label("\(folders.count)", systemImage: "folder.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("\(folders.count) folder\(folders.count == 1 ? "" : "s")")
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(UIColor.secondarySystemBackground))
        .overlay(
            Rectangle()
                .stroke(Color(UIColor.separator).opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Joke Row View (List)

struct JokeRowView: View {
    let joke: Joke
    var roastMode: Bool = false
    var showFullContent: Bool = true
    
    private var isHit: Bool { joke.isHit }
    private var isOpenMic: Bool { joke.isOpenMic }

    private var resolvedTitle: String {
        let explicit = joke.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        let generated = KeywordTitleGenerator.displayTitle(from: joke.content)
        return generated.isEmpty ? "Untitled" : generated
    }

    private var contentPreview: String {
        joke.content
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isHit || isOpenMic ? Color.bitbinderAccent : Color(UIColor.separator).opacity(0.55))
                .frame(width: 4, height: 42)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(resolvedTitle)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if isHit {
                        JokeStatusBadge(text: "Hit", icon: "star.fill")
                    } else if isOpenMic {
                        JokeStatusBadge(text: "Stage", icon: "mic.fill")
                    }
                }

                HStack(spacing: 8) {
                    Text(joke.dateModified.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if showFullContent && !contentPreview.isEmpty {
                        Text(contentPreview)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Joke Status Indicators

private struct JokeStatusGlyph: View {
    let icon: String
    let accessibilityLabel: String

    var body: some View {
        Image(systemName: icon)
            .font(.caption.weight(.bold))
            .foregroundColor(Color.bitbinderAccent)
            .frame(width: 22, height: 22)
            .background(Color.bitbinderAccent.opacity(0.12), in: Circle())
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct JokeStatusBadge: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundColor(Color.bitbinderAccent)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.bitbinderAccent.opacity(0.10), in: Capsule())
    }
}

// MARK: - Folder Chip

struct FolderChip: View {
    let name: String
    var icon: String = "folder.fill"
    let isSelected: Bool
    var roastMode: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            haptic(.selection)
            action()
        }) {
            Text(name)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? (roastMode ? AnyShapeStyle(FirePalette.core) : AnyShapeStyle(Color.accentColor))
                        : AnyShapeStyle(Color(UIColor.tertiarySystemFill))
                )
                .clipShape(Capsule())
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hits Chip

struct TheHitsChip: View {
    let count: Int
    let isSelected: Bool
    var roastMode: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            haptic(.selection)
            action()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? .white : Color.accentColor)

                Text("Hits")
                    .font(.subheadline.weight(.semibold))
                
                if count > 0 && !isSelected {
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color.bitbinderAccent)
                }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.bitbinderAccent)
                    : AnyShapeStyle(Color(UIColor.tertiarySystemFill))
            )
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag Filter Chip

struct TagFilterChip: View {
    let activeTag: String?
    let isSelected: Bool
    var roastMode: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            haptic(.selection)
            action()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? .white : Color.accentColor)

                Text(activeTag.map { "#\($0)" } ?? "Tags")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.bitbinderAccent)
                    : AnyShapeStyle(Color(UIColor.tertiarySystemFill))
            )
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Jokes Empty State

struct JokesEmptyState: View {
    var roastMode: Bool = false
    var hasFilter: Bool = false
    var onAddJoke: (() -> Void)? = nil
    
    var body: some View {
        BitBinderEmptyState(
            icon: roastMode ? "flame" : "text.quote",
            title: hasFilter ? "No jokes here" : (roastMode ? "No roasts yet" : "No jokes yet"),
            subtitle: hasFilter
                ? "Try a different filter or search term"
                : (roastMode ? "Add your first roast target to start" : "Start writing your first joke or import from files"),
            actionTitle: hasFilter ? nil : (roastMode ? "Add Target" : "Add Joke"),
            action: onAddJoke,
            roastMode: roastMode
        )
    }
}

// MARK: - Import Progress Card

struct ImportProgressCard: View {
    let importFileCount: Int
    let importFileIndex: Int
    let importStatusMessage: String
    let importedJokeNames: [String]
    var roastMode: Bool = false
    
    @State private var startDate = Date()
    
    private static let importTips = [
        "Typed text extracts better than handwriting",
        "One joke per paragraph gets the best results",
        "PDFs with clear text work great",
        "Good lighting helps photo imports",
        "High-contrast pages scan best",
    ]
    
    private func tipIndex(for date: Date) -> Int {
        let elapsed = date.timeIntervalSince(startDate)
        return Int(elapsed / 5.0)
    }
    
    private var currentStage: ImportStage {
        let lower = importStatusMessage.lowercased()
        if lower.contains("found") { return .finishing }
        if lower.contains("extract") || lower.contains("gaggrabber") { return .extracting }
        if lower.contains("scan") || lower.contains("analyz") || lower.contains("loading") { return .reading }
        return .analyzing
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Progress indicator
            ProgressView()
                .scaleEffect(1.2)
            
            // Title
            Text(currentStage.title)
                .font(.headline)
            
            // Stage indicators
            HStack(spacing: 4) {
                ForEach(ImportStage.allCases, id: \.self) { stage in
                    stagePill(stage)
                }
            }
            
            // Progress bar
            VStack(spacing: 8) {
                if importFileCount > 1 {
                    Text("File \(importFileIndex) of \(importFileCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ProgressView(value: Double(importFileIndex), total: Double(max(1, importFileCount)))
                    .tint(roastMode ? FirePalette.core : .accentColor)
                
                Text(importStatusMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Recent imports
            if !importedJokeNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found so far:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(importedJokeNames.suffix(3), id: \.self) { name in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(Color.bitbinderAccent)
                            Text(name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Rotating tip
            TimelineView(.periodic(from: .now, by: 5.0)) { context in
                let currentTipIndex = tipIndex(for: context.date)
                Text(Self.importTips[currentTipIndex % Self.importTips.count])
                    .font(.caption)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .multilineTextAlignment(.center)
                    .id(currentTipIndex)
                    .animation(.easeInOut(duration: 0.3), value: currentTipIndex)
            }
        }
        .padding(20)
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private func stagePill(_ stage: ImportStage) -> some View {
        let isActive = stage == currentStage
        let isComplete = stage.rawValue < currentStage.rawValue
        
        return HStack(spacing: 2) {
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(stage.shortLabel)
                .font(.caption2)
                .fontWeight(isActive ? .semibold : .regular)
        }
        .foregroundColor(
            isActive ? .white : (isComplete ? Color.accentColor : .secondary)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            isActive
                ? AnyShapeStyle(Color.accentColor)
                : (isComplete
                    ? AnyShapeStyle(Color.bitbinderAccent.opacity(0.12))
                    : AnyShapeStyle(Color(UIColor.tertiarySystemFill)))
        )
        .clipShape(Capsule())
    }
}

// MARK: - Import Stage

enum ImportStage: Int, CaseIterable {
    case analyzing = 0
    case reading = 1
    case extracting = 2
    case finishing = 3
    
    var title: String {
        switch self {
        case .analyzing: return "Analyzing File..."
        case .reading: return "Reading Content..."
        case .extracting: return "Extracting..."
        case .finishing: return "Almost Done..."
        }
    }
    
    var shortLabel: String {
        switch self {
        case .analyzing: return "Analyze"
        case .reading: return "Read"
        case .extracting: return "Extract"
        case .finishing: return "Finish"
        }
    }
}

// MARK: - View Mode Enum

enum JokesViewMode: String, CaseIterable {
    case list = "List"
    case grid = "Grid"
    
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

// MARK: - Previews

#Preview("Joke Card") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        JokeCardView(joke: Joke(content: "Why did the chicken cross the road? To get to the other side!", title: "Classic Chicken"))
        JokeCardView(joke: {
            let j = Joke(content: "I told my wife she was drawing her eyebrows too high. She looked surprised.", title: "Eyebrow Joke")
            j.isHit = true
            return j
        }())
    }
    .padding()
}

#Preview("Joke Row") {
    List {
        JokeRowView(joke: Joke(content: "Why did the chicken cross the road? To get to the other side!", title: "Classic Chicken"))
        JokeRowView(joke: {
            let j = Joke(content: "I told my wife she was drawing her eyebrows too high. She looked surprised.", title: "Eyebrow Joke")
            j.isHit = true
            return j
        }())
    }
    .listStyle(.insetGrouped)
}
// MARK: - Tag Filter Sheet
//
// Native picker sheet for filtering jokes by an arbitrary tag. Uses standard
// inset-grouped list, system search, and ContentUnavailableView for the empty
// state — matches Apple's HIG patterns.
struct TagFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let allTags: [String]
    let selectedTag: String?
    let onSelect: (String?) -> Void

    @State private var query = ""

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return allTags }
        return allTags.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allTags.isEmpty {
                    ContentUnavailableView(
                        "No Tags Yet",
                        systemImage: "tag",
                        description: Text("Tags appear here once you add them to a joke.")
                    )
                } else {
                    List {
                        Section {
                            Button {
                                onSelect(nil)
                            } label: {
                                HStack {
                                    Label("All Tags", systemImage: "tray.full")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedTag == nil {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }

                        Section {
                            if filtered.isEmpty {
                                Text("No tags match \"\(query)\"")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(filtered, id: \.self) { tag in
                                    Button {
                                        onSelect(tag)
                                    } label: {
                                        HStack {
                                            Text("#\(tag)")
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            if selectedTag == tag {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.tint)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tags")
                }
            }
            .navigationTitle("Filter by Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
