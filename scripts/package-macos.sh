#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.0.0}"
DERIVED_DATA="$ROOT_DIR/.build/distribution"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Release"
BUILT_APP="$PRODUCTS_DIR/DeepForest-macOS.app"
STAGE_DIR="$ROOT_DIR/dist/stage"
STAGED_APP="$STAGE_DIR/DeepForest.app"
ARCHIVE="$ROOT_DIR/dist/DeepForest-${VERSION}-macOS.zip"

cd "$ROOT_DIR"

command -v xcodegen >/dev/null || {
  echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
}

rm -rf "$DERIVED_DATA" "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$ROOT_DIR/dist"

xcodegen generate

xcodebuild \
  -project DeepForest.xcodeproj \
  -scheme DeepForest-macOS \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

[[ -d "$BUILT_APP" ]] || {
  echo "Built app not found at $BUILT_APP" >&2
  exit 1
}

/usr/bin/ditto "$BUILT_APP" "$STAGED_APP"

# Apply an ad-hoc signature so the copied bundle has a complete resource seal.
# Friends will still need to use right-click -> Open because this is not a
# notarized Developer ID build.
/usr/bin/codesign --force --deep --sign - "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"

# Runtime data must never be packaged. Deep Forest stores it under the user's
# Application Support directory, outside the app bundle.
if find "$STAGED_APP" -type f \( \
  -name '*.store' -o \
  -name '*.store-*' -o \
  -name '*.sqlite' -o \
  -name '*.sqlite-*' -o \
  -name '*.db' -o \
  -name '*Backup*.json' \
\) | grep -q .; then
  echo "Refusing to package: a runtime data file was found inside the app bundle." >&2
  exit 1
fi

rm -f "$ARCHIVE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$ARCHIVE"

printf '\nCreated clean distribution archive:\n%s\n' "$ARCHIVE"
printf '\nSHA-256:\n'
/usr/bin/shasum -a 256 "$ARCHIVE"
printf '\nArchitectures:\n'
/usr/bin/lipo -archs "$STAGED_APP/Contents/MacOS/DeepForest-macOS"
