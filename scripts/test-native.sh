#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/native-tests verification
xcrun swiftc -parse-as-library macos/Ade/Domain.swift macos/Ade/Rules.swift macos/Ade/LocalStore.swift macos/Ade/NativePDF.swift macos/Ade/AppModel.swift native-tests/CoreTests.swift -o build/native-tests/CoreTests
build/native-tests/CoreTests
