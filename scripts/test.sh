#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
DEVELOPER_PATH="$(xcode-select -p)"
if [[ "$DEVELOPER_PATH" == */CommandLineTools ]]; then
    FRAMEWORKS="$DEVELOPER_PATH/Library/Developer/Frameworks"
    TESTING_LIBS="$DEVELOPER_PATH/Library/Developer/usr/lib"
else
    FRAMEWORKS="$DEVELOPER_PATH/Platforms/MacOSX.platform/Developer/Library/Frameworks"
    TESTING_LIBS="$DEVELOPER_PATH/Platforms/MacOSX.platform/Developer/usr/lib"
fi
swift test --disable-sandbox --disable-xctest --enable-swift-testing \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$TESTING_LIBS"
