import Foundation

extension Notification.Name {
    static let jokeDatabaseDidChange = Notification.Name("JokeDatabaseDidChange")
    /// Published by BitBuddyService when an add_joke action is dispatched.
    /// userInfo keys: "jokeText" (String), "folder" (String?, optional).
    static let bitBuddyAddJoke = Notification.Name("BitBuddyAddJoke")
    /// Published by BitBuddyService when the user asks to import a file
    /// via chat. The BitBuddyChatView listens for this to open the document picker.
    static let bitBuddyTriggerFileImport = Notification.Name("BitBuddyTriggerFileImport")
}
