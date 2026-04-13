//
//  HelpFAQView.swift
//  thebitbinder
//
//  In-app Help & FAQ screen
//

import SwiftUI

struct HelpFAQView: View {
    @AppStorage("roastModeEnabled") private var roastMode = false
    @State private var searchText = ""
    @State private var expandedItem: String? = nil

    var body: some View {
        List {
            ForEach(filteredSections) { section in
                Section {
                    ForEach(section.items) { item in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedItem == item.id },
                                set: { expandedItem = $0 ? item.id : nil }
                            )
                        ) {
                            Text(item.answer)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } label: {
                            Text(item.question)
                                .font(.subheadline.weight(.medium))
                        }
                    }
                } header: {
                    Label(section.title, systemImage: section.icon)
                }
            }

            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("BitBinder v10.4")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text("Shut up and write some jokes.")
                            .font(.caption)
                            .italic()
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                    Spacer()
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search help")
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Filter all FAQ items by search text
    private var filteredSections: [FAQSectionModel] {
        if searchText.isEmpty { return FAQData.sections }
        return FAQData.sections.compactMap { section in
            let items = section.items.filter {
                $0.question.localizedCaseInsensitiveContains(searchText) ||
                $0.answer.localizedCaseInsensitiveContains(searchText)
            }
            return items.isEmpty ? nil : FAQSectionModel(title: section.title, icon: section.icon, items: items)
        }
    }
}