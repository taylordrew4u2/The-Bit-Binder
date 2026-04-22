import Foundation

extension Notification.Name {
    static let jokeDatabaseDidChange = Notification.Name("JokeDatabaseDidChange")

    // MARK: - Joke Actions
    /// Published by BitBuddyService when an add_joke action is dispatched.
    /// userInfo keys: "jokeText" (String), "folder" (String?, optional).
    static let bitBuddyAddJoke = Notification.Name("BitBuddyAddJoke")
    // MARK: - Brainstorm Actions
    /// userInfo: "text" (String)
    static let bitBuddyAddBrainstormNote = Notification.Name("BitBuddyAddBrainstormNote")

    // MARK: - Set List Actions
    /// userInfo: "name" (String)
    static let bitBuddyCreateSetList = Notification.Name("BitBuddyCreateSetList")

    // MARK: - Folder Actions
    /// userInfo: "name" (String)
    static let bitBuddyCreateFolder = Notification.Name("BitBuddyCreateFolder")

    // MARK: - Roast Actions
    /// userInfo: "name" (String), "notes" (String?, optional)
    static let bitBuddyCreateRoastTarget = Notification.Name("BitBuddyCreateRoastTarget")
    /// userInfo: "joke" (String), "target" (String?, optional)
    static let bitBuddyAddRoastJoke = Notification.Name("BitBuddyAddRoastJoke")

    // MARK: - Notebook Actions
    /// userInfo: "text" (String)
    static let bitBuddySaveNotebookText = Notification.Name("BitBuddySaveNotebookText")

    // MARK: - Import Actions
    /// Published by BitBuddyService when the user asks to import a file
    /// via chat. The BitBuddyChatView listens for this to open the document picker.
    static let bitBuddyTriggerFileImport = Notification.Name("BitBuddyTriggerFileImport")

    // MARK: - Navigation Actions
    /// Published when BitBuddy wants to navigate to a specific app section.
    /// userInfo: "section" (BitBuddySection.rawValue as String)
    static let bitBuddyNavigateToSection = Notification.Name("BitBuddyNavigateToSection")

}
