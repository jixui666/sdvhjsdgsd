#!/bin/bash
set -euo pipefail

# Usage: build_ipa.sh <arch> <output-name>
#   ./scripts/build_ipa.sh arm64e lara        -> build/lara.ipa      (pipeline, iOS >= 26.2)
#   ./scripts/build_ipa.sh arm64  lara-arm64  -> build/lara-arm64.ipa (business-only, iOS < 26.2)
ARCHS="${1:-arm64e}"
OUTNAME="${2:-lara}"

rm -rf build/
mkdir -p build

echo "Build Started (arch=$ARCHS, output=$OUTNAME.ipa)!"
echo

xcodebuild \
  -project lara.xcodeproj \
  -scheme lara \
  -configuration Debug \
  -sdk iphoneos \
  -arch "$ARCHS" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="Config/lara.entitlements" \
  archive \
  -archivePath "$PWD/build/lara.xcarchive" 2>&1 | tee build/xcodebuild.log

APP_PATH="$PWD/build/lara.xcarchive/Products/Applications/lara.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Missing app at $APP_PATH"
  exit 1
fi
rm -rf "$PWD/build/Payload"
mkdir -p "$PWD/build/Payload"
cp -R "$APP_PATH" "$PWD/build/Payload/"

plutil -replace UIFileSharingEnabled -bool YES "$PWD/build/Payload/lara.app/Info.plist"

if ! command -v ldid >/dev/null 2>&1; then
  echo "ERROR: ldid not installed. Install with: brew install ldid" >&2
  exit 1
fi
ldid -SConfig/lara.entitlements "$PWD/build/Payload/lara.app/lara"
(cd "$PWD/build" && /usr/bin/zip -qry "$OUTNAME.ipa" Payload)

echo
echo "build successful!"
echo "ipa at: build/$OUTNAME.ipa"
exit 0
