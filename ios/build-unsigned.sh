#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodegen >/dev/null
xcodebuild -version
xcodegen generate
xcodebuild -project PrivateAssistant.xcodeproj \
  -scheme PrivateAssistant -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$PWD/.build" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
app="$PWD/.build/Build/Products/Release-iphoneos/PrivateAssistant.app"
test -f "$app/Info.plist"
test -f "$app/PrivateAssistant"
# Xcode generated plists can omit unknown or new INFOPLIST_KEY settings.
# The explicit source plist must survive the final build; fail rather than ship a broken permission.
for key in NSAlarmKitUsageDescription NSHealthShareUsageDescription NSAppleMusicUsageDescription NSCalendarsFullAccessUsageDescription NSRemindersFullAccessUsageDescription; do
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$app/Info.plist")"
  test -n "$value"
  echo "Verified permission declaration: $key"
done
# Verify the binary is for an actual iPhone, not a simulator.
xcrun vtool -show-build "$app/PrivateAssistant"
xcrun lipo -verify_arch arm64 "$app/PrivateAssistant"
mkdir -p "$PWD/dist"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/Payload"
ditto "$app" "$stage/Payload/PrivateAssistant.app"
rm -f "$PWD/dist/PrivateAssistant-unsigned.ipa"
(cd "$stage" && zip -qry "$OLDPWD/dist/PrivateAssistant-unsigned.ipa" Payload)
unzip -t "$PWD/dist/PrivateAssistant-unsigned.ipa"
shasum -a 256 "$PWD/dist/PrivateAssistant-unsigned.ipa" > "$PWD/dist/PrivateAssistant-unsigned.ipa.sha256"
echo "Unsigned IPA created. Requires device signing. No credentials embedded."
