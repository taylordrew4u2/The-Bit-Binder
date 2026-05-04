import Foundation

enum QuickCaptureDraftStore {
    private enum Key {
        static let addJoke = "quick_capture.add_joke"
        static let brainstorm = "quick_capture.brainstorm"
        static let talkToTextJoke = "quick_capture.talk_to_text.joke"
        static let talkToTextBrainstorm = "quick_capture.talk_to_text.brainstorm"
        static let talkToTextRoast = "quick_capture.talk_to_text.roast"
    }

    private struct JokeDraft: Codable {
        let title: String
        let content: String
    }

    static func loadJokeDraft() -> (title: String, content: String)? {
        guard
            let data = UserDefaults.standard.data(forKey: Key.addJoke),
            let draft = try? JSONDecoder().decode(JokeDraft.self, from: data)
        else {
            return nil
        }
        return (draft.title, draft.content)
    }

    static func saveJokeDraft(title: String, content: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedContent.isEmpty else {
            clearJokeDraft()
            return
        }

        let draft = JokeDraft(title: title, content: content)
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: Key.addJoke)
    }

    static func clearJokeDraft() {
        UserDefaults.standard.removeObject(forKey: Key.addJoke)
    }

    static func loadBrainstormDraft() -> String? {
        UserDefaults.standard.string(forKey: Key.brainstorm)
    }

    static func saveBrainstormDraft(_ content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearBrainstormDraft()
            return
        }
        UserDefaults.standard.set(content, forKey: Key.brainstorm)
    }

    static func clearBrainstormDraft() {
        UserDefaults.standard.removeObject(forKey: Key.brainstorm)
    }

    static func loadTalkToTextDraft(saveToBrainstorm: Bool) -> String? {
        UserDefaults.standard.string(forKey: saveToBrainstorm ? Key.talkToTextBrainstorm : Key.talkToTextJoke)
    }

    static func saveTalkToTextDraft(_ content: String, saveToBrainstorm: Bool) {
        let key = saveToBrainstorm ? Key.talkToTextBrainstorm : Key.talkToTextJoke
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(content, forKey: key)
    }

    static func clearTalkToTextDraft(saveToBrainstorm: Bool) {
        let key = saveToBrainstorm ? Key.talkToTextBrainstorm : Key.talkToTextJoke
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func loadTalkToTextRoastDraft() -> String? {
        UserDefaults.standard.string(forKey: Key.talkToTextRoast)
    }

    static func saveTalkToTextRoastDraft(_ content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearTalkToTextRoastDraft()
            return
        }
        UserDefaults.standard.set(content, forKey: Key.talkToTextRoast)
    }

    static func clearTalkToTextRoastDraft() {
        UserDefaults.standard.removeObject(forKey: Key.talkToTextRoast)
    }
}
