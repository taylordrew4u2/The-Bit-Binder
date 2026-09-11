#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/bitbinder-tests.XXXXXX")"
trap 'rm -r "$test_build_dir"' EXIT
xcrun swiftc thebitbinder/Utilities/JokeEditorPersistence.swift Tests/JokeEditor/PersistenceRegression.swift -o "$test_build_dir/persistence"
"$test_build_dir/persistence"
xcrun swiftc thebitbinder/Utilities/AutoSaveManager.swift Tests/SwiftUI/AutoSaveRegression.swift -o "$test_build_dir/autosave"
"$test_build_dir/autosave"
xcrun swiftc thebitbinder/Utilities/VisibleListOrder.swift Tests/SwiftUI/ListOrderRegression.swift -o "$test_build_dir/list-order"
"$test_build_dir/list-order"
xcrun swiftc thebitbinder/Utilities/EditableTextRow.swift Tests/SwiftUI/EditableRowsRegression.swift -o "$test_build_dir/editable-rows"
"$test_build_dir/editable-rows"
