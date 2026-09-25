import AppIntents
import SwiftUI

struct SiriShortcutsView: View {
    var body: some View {
        List {
            Section {
                Text("Capture an idea as it arrives, find a joke, or pull up your sets with Siri.")
                    .foregroundStyle(.secondary)
            }

            Section("Try saying") {
                command("Save a joke", symbol: "square.and.pencil",
                        phrase: "Save a joke in BitBinder",
                        detail: "Siri asks for your joke, then saves it to your library.")
                command("Find jokes", symbol: "magnifyingglass",
                        phrase: "Find jokes in BitBinder",
                        detail: "Tell Siri what to search for. BitBinder opens the matching jokes.")
                command("Open sets", symbol: "list.number",
                        phrase: "Open my sets in BitBinder",
                        detail: "Open your set lists, ready to review or rehearse.")
            }

            Section {
                ShortcutsLink()
            } header: {
                Text("Make it your own")
            } footer: {
                Text("Find BitBinder in Shortcuts to use these actions in your own shortcuts. Your device must be unlocked to access your writing. Siri needs to be enabled in your device settings.")
            }

            #if !targetEnvironment(macCatalyst)
            Section {
                SiriTipView(intent: SaveJokeIntent())
            }
            .listRowBackground(Color.clear)
            #endif
        }
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func command(_ title: String, symbol: String, phrase: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text("“\(phrase)”")
                .font(.body)
                .textSelection(.enabled)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
