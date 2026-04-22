import Foundation

struct FAQSectionModel: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let items: [FAQItem]
}

struct FAQItem: Identifiable {
    let id: String
    let question: String
    let answer: String

    init(_ question: String, _ answer: String) {
        self.id = question
        self.question = question
        self.answer = answer
    }
}

enum FAQData {
    static let sections: [FAQSectionModel] = [
        FAQSectionModel(title: "Getting Started", icon: "star.fill", items: [
            FAQItem("What is BitBinder?",
                    "BitBinder is your pocket comedy notebook. Write jokes, brainstorm ideas, record sets, build set lists, and roast your friends — all in one place."),
            FAQItem("How do I add my first joke?",
                    "Tap the Jokes section from the menu, then tap the + button. Give it a title, write the content, and save. That's it."),
            FAQItem("What is the Home screen for?",
                    "Home is your launchpad — see recent work, quick-capture new jokes, and jump to your set lists. Tap 'New Joke' to write or 'Quick Idea' to dictate."),
            FAQItem("How do I switch between sections?",
                    "Tap any tab along the bottom of the screen. Settings is always the last tab. Customize which tabs appear in Settings → Customize App."),
        ]),
        FAQSectionModel(title: "Jokes & Folders", icon: "theatermask.and.paintbrush.fill", items: [
            FAQItem("How do I create a folder for jokes?",
                    "In the Jokes section, tap the overflow menu (•••), then tap the + folder option in the toolbar. Name it and it appears as a filter chip at the top."),
            FAQItem("What is The Hits?",
                    "The Hits is a special chip that shows jokes you've marked as 'stage-ready'. Tap the star icon on any joke to mark it as a hit."),
            FAQItem("How do I switch between Grid and List view?",
                    "Tap the grid/list icon in the overflow menu (•••) in the Jokes toolbar. Your preference is saved between sessions."),
            FAQItem("Can I move a joke to a different folder?",
                    "Yes — tap a joke to open it, tap Edit, and change the folder assignment."),
            FAQItem("How do I delete a joke?",
                    "Swipe left on the joke row in list view, or tap Edit inside the joke detail view. Deleted jokes go to Trash first and can be recovered."),
            FAQItem("How do I select multiple jokes?",
                    "Tap the overflow menu (•••) and choose 'Select Multiple'. Then tap jokes to select them and use the batch actions to delete or move."),
        ]),
        FAQSectionModel(title: "Brainstorm", icon: "lightbulb.fill", items: [
            FAQItem("What is the Brainstorm section?",
                    "A sticky-note grid for capturing raw ideas before they become full jokes. Tap + to write or use the mic button to capture ideas by voice."),
            FAQItem("How do I add a brainstorm idea?",
                    "Tap the + button in the bottom-right corner. Type your idea and tap Save."),
            FAQItem("Can I record ideas by voice?",
                    "Yes — tap the mic button next to the + button. It transcribes your voice in real time and saves it as a thought when you stop."),
            FAQItem("How do I promote an idea to a joke?",
                    "Long-press an idea card to see the context menu, then tap 'Promote to Joke'. The idea becomes a full joke and moves to your Jokes section."),
            FAQItem("How do I delete an idea?",
                    "Long-press the idea card and tap Delete, or use Select Multiple mode from the overflow menu (•••) to batch delete."),
        ]),
        FAQSectionModel(title: "Set Lists", icon: "list.bullet.rectangle.portrait.fill", items: [
            FAQItem("What is a Set List?",
                    "A Set List is an ordered collection of jokes for a specific show or open mic. Think of it as a setlist for your comedy set."),
            FAQItem("How do I create a set list?",
                    "Tap the + button in the Set Lists section, give it a name, then add jokes from your library."),
            FAQItem("Can I reorder jokes in a set list?",
                    "Yes — open the set list and long-press then drag any joke to reorder it."),
            FAQItem("What does finalized mean?",
                    "A finalized set list shows a green checkmark and indicates you're happy with the order. It's just for your own tracking."),
        ]),
        FAQSectionModel(title: "Recordings", icon: "waveform.circle.fill", items: [
            FAQItem("How do I record a set?",
                    "Go to Recordings and tap the mic button (top-right) or the + button. Press stop when done. The recording is saved with a timestamp."),
            FAQItem("Can I transcribe a recording?",
                    "Yes — open a recording and tap the transcribe button. It uses Apple's on-device speech recognition."),
            FAQItem("How do I export my recordings?",
                    "Go to Settings → Data Protection → Export All Audio Files to share or save as a zip archive."),
        ]),
        FAQSectionModel(title: "Roast Mode", icon: "flame.fill", items: [
            FAQItem("What is Roast Mode?",
                    "Roast Mode transforms the entire app into a dedicated roasting environment with a dark ember theme. The menu shows Roasts and Settings only."),
            FAQItem("How do I turn on Roast Mode?",
                    "Go to Settings and toggle Roast Mode on. The entire app instantly switches themes."),
            FAQItem("Are roast jokes separate from regular jokes?",
                    "Yes — roasts are stored completely separately and only visible when Roast Mode is on. Your regular jokes stay safe."),
            FAQItem("How do I add a roast target?",
                    "In Roast Mode, go to the Roasts section and tap + to add a target. Then add roast jokes under that person."),
        ]),
        FAQSectionModel(title: "iCloud Sync", icon: "icloud.and.arrow.up.fill", items: [
            FAQItem("How do I enable iCloud Sync?",
                    "Go to Settings → iCloud Sync → toggle Enable iCloud Sync. Make sure you're signed into iCloud on your device."),
            FAQItem("What gets synced to iCloud?",
                    "Jokes, roasts, set lists, recordings, notebook photos, and your brainstorm ideas are all synced."),
            FAQItem("Does syncing happen automatically?",
                    "Yes — once enabled, data syncs in the background whenever changes are made. You can also tap Sync Now for an immediate sync."),
            FAQItem("My sync isn't working. What do I do?",
                    "Check that you're signed into iCloud in Settings → [Your Name] → iCloud, and that BitBinder has iCloud access enabled."),
        ]),
        FAQSectionModel(title: "Data Protection", icon: "shield.checkered", items: [
            FAQItem("Where is Data Protection?",
                    "Go to Settings → Data Protection. Here you can create backups, restore from backups, and export your data."),
            FAQItem("How do I create a backup?",
                    "In Data Protection, tap 'Create Backup'. This saves a snapshot of all your data locally."),
            FAQItem("Can I restore from a backup?",
                    "Yes — tap 'View Backups' to see all available backups. Tap Restore on any backup to recover your data."),
            FAQItem("How do I export my jokes?",
                    "In Data Protection, tap 'Export All Jokes'. Choose to save as PDF, email, or share."),
        ]),
        FAQSectionModel(title: "Trash & Recovery", icon: "trash.fill", items: [
            FAQItem("Where is the Trash?",
                    "Go to Settings → Trash. You'll see how many deleted jokes are available for recovery."),
            FAQItem("Can I recover deleted jokes?",
                    "Yes! Deleted items go to Trash first. Open Trash, find your item, and tap Restore to bring it back."),
            FAQItem("How long do items stay in Trash?",
                    "Items remain in Trash until you permanently delete them or restore them. They won't auto-delete."),
            FAQItem("Each section has its own trash?",
                    "Yes — each section (Jokes, Brainstorm, Set Lists, Recordings) has its own Trash accessible from the overflow menu (•••)."),
        ]),
        FAQSectionModel(title: "BitBuddy", icon: "bubble.left.and.bubble.right.fill", items: [
            FAQItem("What is BitBuddy?",
                    "BitBuddy is your on-device comedy writing sidekick. It handles analyze / improve / premise / generate commands, plus quick workflow help — all from a chat pane that rides alongside whatever you're working on."),
            FAQItem("How do I open BitBuddy?",
                    "Tap the BitBuddy avatar floating on any screen. A chat pane slides in from the right so you can ask things without leaving your current joke."),
            FAQItem("What commands can I use?",
                    "• analyze: [joke] — Get structure, strengths, and edit suggestions\n• improve: [joke] — Get 2-3 concrete edit suggestions\n• premise [topic] — Generate a premise for a topic\n• generate [topic] — Create a joke matching your style\n• style — See your writing style summary"),
            FAQItem("Does BitBuddy use the internet?",
                    "BitBuddy runs entirely on your device. Your joke content stays on your phone unless you explicitly export or share it."),
        ]),
        FAQSectionModel(title: "Importing Jokes", icon: "square.and.arrow.down.fill", items: [
            FAQItem("What file types can I import?",
                    "PDF, images (JPEG, PNG, HEIC), Word docs (.doc, .docx), and plain text files (.txt, .rtf)."),
            FAQItem("How does the smart import work?",
                    "GagGrabber reads your file and intelligently splits it into individual jokes. It looks for separators like 'NEXT JOKE', '---', numbered lists, bullet points, and blank lines."),
            FAQItem("What's the Review Queue?",
                    "Jokes that GagGrabber isn't 100% sure about go to the Review Queue. You can approve, edit, or reject them before they're saved."),
            FAQItem("Where do I see my import history?",
                    "In the Jokes section, tap the overflow menu (•••) and choose 'Import History' to see all your past imports."),
        ]),
        FAQSectionModel(title: "Account & Privacy", icon: "person.circle.fill", items: [
            FAQItem("Do I need an account?",
                    "No — the app works fully offline without an account. Sign into iCloud to unlock sync features across devices."),
            FAQItem("How do I export all my jokes?",
                    "Settings → Data Protection → Export All Jokes. Choose PDF, email, or share sheet."),
            FAQItem("Is my data private?",
                    "Your data is stored locally on your device and optionally in your private iCloud account. Nothing is shared with third parties."),
            FAQItem("What about voice recordings?",
                    "Voice transcription uses Apple's on-device speech recognition. Audio never leaves your device unless you explicitly share it."),
        ]),
    ]

}
