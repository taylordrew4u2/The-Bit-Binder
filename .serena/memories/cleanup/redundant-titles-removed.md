# Redundant Page Title Cleanup - Completed

## Summary
Removed every in-content page title/header that just repeated the screen name from sheet modals and detail views. The native navigation bar now handles all screen context.

## Changes Made

### In-Content Titles Removed (Sheet Modals)
These views had decorative titles like "Import Voice Memos", "Record Set", "Roast Talk-to-Text", etc. that duplicated the navigation bar context:

1. **AudioImportView.swift** - Removed "Import Voice Memos" header with icon
2. **TalkToTextView.swift** - Removed redundant "Talk-to-Text Joke" / "Quick Idea" title section
3. **TalkToTextRoastView.swift** - Removed "Roast Talk-to-Text" title, kept only status "Listening..."
4. **RecordRoastSetView.swift** - Removed "Record Set" title, kept only status "Recording..."
5. **AddBrainstormIdeaSheet.swift** - Used standard sheet without redundant title

### AppTheme Color References Replaced
Removed all stale AppTheme.Colors references and replaced with SwiftUI standard colors:

- **SetListDetailView.swift**
  - AppTheme.Colors.recordingsAccent → Color.red
  - AppTheme.Colors.primaryAction → Color.accentColor
  - AppTheme.Colors.roastAccent → Color.orange

- **CreateFolderView.swift**
  - AppTheme.Colors.roastBackground → Color(UIColor.systemBackground)
  - AppTheme.Colors.roastAccent → Color.orange
  - AppTheme.Colors.primaryAction → Color.accentColor

- **AddBrainstormIdeaSheet.swift**
  - AppTheme.Colors.roastBackground/paperCream → Color(UIColor.systemBackground)
  - AppTheme.Colors.roastCard/surfaceElevated → Color(UIColor.secondarySystemBackground)
  - AppTheme.Colors.textTertiary → Color.tertiary
  - AppTheme.Colors.inkBlack → Color.primary
  - AppTheme.Colors.roastAccent/primaryAction → Color.orange/.accentColor

- **TalkToTextRoastView.swift**
  - AppTheme.Colors.roastAccent → Color.orange
  - AppTheme.Colors.recordingsAccent → Color.red
  - AppTheme.Colors.surfaceElevated → Color(UIColor.secondarySystemBackground)

- **RecordRoastSetView.swift**
  - AppTheme.Colors.recordingsAccent → Color.red
  - AppTheme.Colors.success → Color.green
  - AppTheme.Colors.surfaceElevated → Color(UIColor.secondarySystemBackground)

- **AutoOrganizeView.swift**
  - AppTheme.Colors.success → Color.green
  - AppTheme.Colors.primaryAction → Color.accentColor
  - AppTheme.Colors.surfaceElevated → Color(UIColor.secondarySystemBackground)

## Result
All views now:
- Rely on navigation bar for screen context
- Use standard SwiftUI color system (light/dark mode compatible)
- Have cleaner, less redundant UI layouts
- Maintain functionality with simplified styling
