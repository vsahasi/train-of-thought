#!/bin/sh
# Runs the TrainCore tests with only the Command Line Tools installed.
# `swift test` needs Xcode (for XCTest); this builds the core, a tiny XCTest
# stand-in, and the tests with swiftc directly.
set -eu
cd "$(dirname "$0")/.."

OUT=.build/clt-tests
mkdir -p "$OUT"
SDK=$(xcrun --show-sdk-path)
TARGET="$(uname -m)-apple-macos13"
FLAGS="-sdk $SDK -target $TARGET"

swiftc $FLAGS -enable-testing -parse-as-library -emit-module -emit-library -module-name TrainCore \
  -emit-module-path "$OUT/TrainCore.swiftmodule" -o "$OUT/libTrainCore.dylib" \
  -Xlinker -install_name -Xlinker @rpath/libTrainCore.dylib \
  Sources/TrainCore/*.swift

swiftc $FLAGS -parse-as-library -emit-module -emit-library -module-name XCTest \
  -emit-module-path "$OUT/XCTest.swiftmodule" -o "$OUT/libXCTest.dylib" \
  -Xlinker -install_name -Xlinker @rpath/libXCTest.dylib \
  Scripts/xctest-shim/XCTest.swift

# Generate main.swift: one call per `func test…()` in each test class.
MAIN="$OUT/main.swift"
{
  echo "import XCTest"
  for f in Tests/TrainCoreTests/*.swift; do
    cls=$(grep -o 'class [A-Za-z0-9_]*' "$f" | head -1 | awk '{print $2}')
    grep -o 'func test[A-Za-z0-9_]*' "$f" | awk '{print $2}' | while read -r m; do
      echo "xctestShimRun(\"$cls.$m\") { let t = $cls(); t.setUp(); t.$m(); t.tearDown() }"
    done
  done
  echo "xctestShimFinish()"
} > "$MAIN"

swiftc $FLAGS -I "$OUT" -L "$OUT" -lTrainCore -lXCTest \
  -Xlinker -rpath -Xlinker @executable_path \
  Tests/TrainCoreTests/*.swift Scripts/xctest-shim/Runner.swift "$MAIN" -o "$OUT/tests"

exec "$OUT/tests"
