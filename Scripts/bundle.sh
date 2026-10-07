#!/bin/sh
# Builds "Train of Thought.app" into build/ with swiftc directly, so it
# works with just the Command Line Tools. With Xcode, `swift build` works
# too, but only this script produces the .app bundle (menu bar apps need
# one for the icon, launch-at-login and a stable identity).
set -eu
cd "$(dirname "$0")/.."

VERSION=${VERSION:-$(git describe --tags --always 2>/dev/null | sed 's/^v//' || echo 0.0.0)}
ARCHS=${ARCHS:-$(uname -m)}
OUT=.build/bundle
APP="build/Train of Thought.app"
SDK=$(xcrun --show-sdk-path)

mkdir -p "$OUT" build

build_arch() {
  arch=$1
  dir="$OUT/$arch"
  mkdir -p "$dir"
  echo "· TrainCore ($arch)"
  swiftc -sdk "$SDK" -target "$arch-apple-macos13" -O -parse-as-library \
    -emit-library -static -module-name TrainCore \
    -emit-module-path "$dir/TrainCore.swiftmodule" -o "$dir/libTrainCore.a" \
    Sources/TrainCore/*.swift
  echo "· TrainOfThought ($arch)"
  swiftc -sdk "$SDK" -target "$arch-apple-macos13" -O -module-name TrainOfThought \
    -I "$dir" -L "$dir" -lTrainCore \
    Sources/TrainOfThought/*.swift Sources/TrainOfThought/*/*.swift \
    -o "$dir/TrainOfThought"
}

for arch in $ARCHS; do build_arch "$arch"; done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

set -- $ARCHS
if [ $# -gt 1 ]; then
  inputs=""
  for arch in $ARCHS; do inputs="$inputs $OUT/$arch/TrainOfThought"; done
  lipo -create $inputs -output "$APP/Contents/MacOS/TrainOfThought"
else
  cp "$OUT/$1/TrainOfThought" "$APP/Contents/MacOS/TrainOfThought"
fi

echo "· icon"
first=$(echo $ARCHS | awk '{print $1}')
swiftc -sdk "$SDK" -target "$first-apple-macos13" -O -I "$OUT/$first" -L "$OUT/$first" -lTrainCore \
  Sources/TrainOfThought/Overlay/Pixel.swift Sources/TrainOfThought/Overlay/Sprites.swift Scripts/make-icon/main.swift \
  -o "$OUT/make-icon"
rm -rf "$OUT/AppIcon.iconset"
"$OUT/make-icon" "$OUT/AppIcon.iconset" >/dev/null
iconutil -c icns "$OUT/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Train of Thought</string>
  <key>CFBundleExecutable</key><string>TrainOfThought</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.vsahasi.TrainOfThought</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Train of Thought</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS treats the bundle as a stable identity between
# builds (and launch-at-login works).
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP ($VERSION, $ARCHS)"
