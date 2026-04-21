# Thebitbinder Native iOS Style Guide

## Core Principle
**Default iOS at its best.** No custom visual inventions. Use system components and colors exclusively.

## Color Palette

### Primary Colors (Never Use AppTheme)
```swift
// DO: Use system colors
let primary = Color.accentColor          // System blue
let success = Color.green                // System green
let destructive = Color.red              // System red
let accent = Color.orange                // System orange (roast mode only)

// DON'T: Use custom colors
// AppTheme.Colors.primaryAction          // ❌ Removed
// AppTheme.Colors.success                // ❌ Removed
```

### Background Colors
```swift
// DO: Use system backgrounds
let background = Color(UIColor.systemBackground)
let secondary = Color(UIColor.secondarySystemBackground)
let tertiary = Color(UIColor.tertiarySystemBackground)
let grouped = Color(UIColor.systemGroupedBackground)

// DON'T: Use custom backgrounds
// AppTheme.Colors.roastBackground        // ❌ Removed
// AppTheme.Colors.paperCream             // ❌ Removed
```

### Text Colors
```swift
// DO: Use semantic colors
let primary = Color.primary              // System foreground
let secondary = Color.secondary          // System gray
let tertiary = Color.tertiary            // System light gray

// DON'T: Use custom text colors
// AppTheme.Colors.textTertiary           // ❌ Removed
// AppTheme.Colors.inkBlack               // ❌ Removed
```

## Typography

### Page Titles
```swift
// DO: Use navigationTitle at TabView level
NavigationStack {
    HomeView()
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
}

// DON'T: Add redundant in-content titles
// VStack {
//     Text("Home").font(.title2).bold()    // ❌ Redundant
//     // content...
// }
```

### Section Headers
```swift
// DO: Use Form sections
Form {
    Section("Your Data") {
        TextField("Name", text: $name)
    }
}

// DON'T: Create custom headers
// VStack {
//     Text("Your Data").font(.headline)    // ❌ Use Form instead
// }
```

### Body Text
```swift
// DO: Use system fonts
Text("Your content here")
    .font(.body)
    .lineSpacing(4)              // Improve readability

// DON'T: Use custom fonts or decorative styling
Text("Your content here")
    .font(.system(size: 17))     // ❌ Use .body
    .tracking(0.5)               // ❌ Unnecessary
```

## Components

### Buttons
```swift
// DO: Use native button styles
Button("Save") { saveAction() }
    .buttonStyle(.borderedProminent)
    .tint(.accentColor)

Button("Delete", role: .destructive) { }
    .buttonStyle(.bordered)
    .tint(.red)

// DON'T: Use custom button styles
// Button("Save") { }
//     .buttonStyle(FABButtonStyle())       // ❌ Removed
```

### Forms
```swift
// DO: Use native Form structure
Form {
    Section("Basic Info") {
        TextField("Name", text: $name)
        TextField("Email", text: $email)
    }
    Section("Options") {
        Toggle("Notifications", isOn: $notifications)
    }
}

// DON'T: Build custom layouts for forms
// VStack {
//     ChipStyle { ... }                    // ❌ Use Form + sections
// }
```

### Lists
```swift
// DO: Use native List with sections
List {
    Section("Items") {
        ForEach(items) { item in
            NavigationLink(value: item) {
                Label(item.name, systemImage: item.icon)
            }
        }
    }
}

// DON'T: Use custom card layouts
// VStack {
//     MyCustomCardView()                   // ❌ Use List instead
// }
```

### Toggles
```swift
// DO: Use native Toggle
Toggle("Roast Mode", isOn: $roastMode)
    .tint(roastMode ? .orange : .accentColor)

// DON'T: Create custom toggles
// HStack {
//     CustomToggle()                       // ❌ Use native Toggle
// }
```

## Theming

### Roast Mode Strategy
```swift
// Roast mode uses .orange accent throughout
@AppStorage("roastModeEnabled") private var roastMode = false

private var accent: Color {
    roastMode ? .orange : .accentColor
}

// Apply consistently
Button("Action") { }
    .tint(accent)
    
Toggle("Setting", isOn: $setting)
    .tint(accent)
```

### Light/Dark Mode
```swift
// DO: Let system handle appearance
Text("Content")
    .foregroundColor(.primary)       // Auto-adapts to dark mode

// DON'T: Force colors
Text("Content")
    .foregroundColor(.black)         // ❌ Breaks dark mode
    .background(.white)              // ❌ Breaks dark mode
```

## Navigation

### Tab-Level Titles
```swift
// DO: Set title once at TabView level
TabView {
    NavigationStack {
        HomeView()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
    }
}

// DON'T: Add duplicate titles in HomeView
// var body: some View {
//     VStack {
//         Text("Home").font(.title)         // ❌ Redundant
//         // content...
//     }
// }
```

### Sheet Titles
```swift
// DO: Suppress inline sheet titles
.sheet(isPresented: $show) {
    NavigationStack {
        AddJokeView()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// Sheet provides toolbar title via:
.toolbar {
    ToolbarItem(placement: .confirmationAction) {
        Button("Done") { }
    }
}
```

## Do's and Don'ts

| ✅ DO | ❌ DON'T |
|------|---------|
| Use `.accentColor`, `.green`, `.red`, `.orange` | Use `AppTheme.Colors.*` |
| Use `Form` for data input | Build custom form layouts |
| Use `List` for data display | Use custom card systems |
| Use native `Button`, `Toggle`, `TextField` | Create custom control wrappers |
| Set `.navigationTitle()` once per screen | Add redundant in-content titles |
| Use `.font(.body)`, `.font(.headline)` | Use `.font(.system(size: 17))` |
| Let system handle light/dark appearance | Force specific colors |
| Use `.buttonStyle(.borderedProminent)` | Create custom button styles |

## Deletion History

**Removed Components:**
- ✖️ TouchReactiveStyle.swift
- ✖️ FABButtonStyle.swift
- ✖️ ChipStyle.swift
- ✖️ MenuItemStyle.swift
- ✖️ SmoothScaleButtonStyle.swift
- ✖️ ScaleButtonStyle.swift
- ✖️ AppTheme (color system)
- ✖️ NativeTheme (legacy)

**These are gone forever. Use system components instead.**

## Quick Reference

### Import Only What You Need
```swift
import SwiftUI
import SwiftData
// That's it for UI. No custom style imports needed.
```

### Minimal View Template
```swift
struct MyView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var myData = ""
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    var body: some View {
        Form {
            Section("Title") {
                TextField("Label", text: $myData)
            }
        }
        .tint(roastMode ? .orange : .accentColor)
    }
}
```

---

**Last Updated:** April 6, 2026
**Status:** Native iOS refactor complete
**Next Step:** Follow these guidelines for all new code
