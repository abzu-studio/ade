#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
expected_xcode=$'Xcode 27.0\nBuild version 27A266a'
actual_xcode="$(xcodebuild -version)"
actual_swift="$(xcrun swift --version)"
if [[ "$actual_xcode" != "$expected_xcode" ]] || [[ "$actual_swift" != *'Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)'* ]]; then
  printf '%s\n' 'Toolchain mismatch. Required: Xcode 27.0 (27A266a), Apple Swift 6.4 (swiftlang-6.4.0.34.1).' >&2
  exit 1
fi
printf '%s\n%s\n' "$actual_xcode" "$actual_swift"
