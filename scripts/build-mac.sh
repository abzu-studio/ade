#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodegen generate --spec macos/project.yml
xcodebuild -project macos/Ade.xcodeproj -scheme Ade -configuration Debug -derivedDataPath "${ADE_DERIVED_DATA:-$PWD/build/DerivedData}" CODE_SIGN_IDENTITY=- build
