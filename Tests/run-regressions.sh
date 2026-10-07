#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/bitbinder-tests.XXXXXX")"
trap 'rm -r "$test_build_dir"' EXIT

# swift-collections 1.7.0+ makes Swift 6.4 emit a hard import of _swift_initBorrow,
# which only exists in the iOS 27 runtime. With an iOS 18 deployment target the app
# aborts in dyld at launch on any device below iOS 27. Keep the pin below 1.7.0.
resolved="thebitbinder.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
collections_version="$(python3 - "$resolved" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    pins = json.load(source)["pins"]
print(next(p["state"]["version"] for p in pins if p["identity"] == "swift-collections"))
PY
)"
if [ "$(printf '%s\n' "$collections_version" 1.7.0 | sort -V | head -n1)" = "1.7.0" ]; then
  echo "swift-collections is pinned at $collections_version; it must stay below 1.7.0 (see comment above)" >&2
  exit 1
fi
echo "swift-collections pin OK ($collections_version)"
xcrun swiftc thebitbinder/Utilities/JokeEditorPersistence.swift Tests/JokeEditor/PersistenceRegression.swift -o "$test_build_dir/persistence"
"$test_build_dir/persistence"
xcrun swiftc thebitbinder/Utilities/AutoSaveManager.swift Tests/SwiftUI/AutoSaveRegression.swift -o "$test_build_dir/autosave"
"$test_build_dir/autosave"
xcrun swiftc thebitbinder/Utilities/VisibleListOrder.swift Tests/SwiftUI/ListOrderRegression.swift -o "$test_build_dir/list-order"
"$test_build_dir/list-order"
xcrun swiftc thebitbinder/Utilities/EditableTextRow.swift Tests/SwiftUI/EditableRowsRegression.swift -o "$test_build_dir/editable-rows"
"$test_build_dir/editable-rows"
xcrun swiftc thebitbinder/Utilities/AppScreen.swift Tests/SwiftUI/TabNavigationRegression.swift -o "$test_build_dir/tab-navigation"
"$test_build_dir/tab-navigation"
xcrun swiftc thebitbinder/Utilities/BitBuddyCompactLayout.swift Tests/SwiftUI/BitBuddyCompactLayoutRegression.swift -o "$test_build_dir/compact-layout"
"$test_build_dir/compact-layout"
xcrun swiftc thebitbinder/Utilities/AppTextSize.swift Tests/SwiftUI/TextSizeRegression.swift -o "$test_build_dir/text-size"
"$test_build_dir/text-size"
xcrun swiftc thebitbinder/Utilities/ActionColors.swift Tests/SwiftUI/ActionColorsRegression.swift -o "$test_build_dir/action-colors"
"$test_build_dir/action-colors"
xcrun swiftc thebitbinder/Utilities/JokeEditorPersistence.swift thebitbinder/Utilities/KeywordTitleGenerator.swift thebitbinder/Utilities/SiriJokeCapture.swift Tests/SwiftUI/SiriCaptureRegression.swift -o "$test_build_dir/siri-capture"
"$test_build_dir/siri-capture"
