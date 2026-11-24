#!/bin/bash
# Headless MacInCloud archive + TestFlight upload for CircuitLens.
# Usage: KEYCHAIN_PASSWORD=... ./scripts/archive_upload.sh 68T2S87K39 0803ec59-b64d-4014-9519-d5e8c7079f0c
set -euo pipefail

KEY_ID="${1:-68T2S87K39}"
ISSUER_ID="${2:-0803ec59-b64d-4014-9519-d5e8c7079f0c}"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
[ -f "$KEY_PATH" ] || { echo "Missing $KEY_PATH"; exit 1; }

cd "$(dirname "$0")/.."
ARCHIVE="$HOME/circuit-lens-build/CircuitLens.xcarchive"
mkdir -p "$(dirname "$ARCHIVE")"

if [ -n "${KEYCHAIN_PASSWORD:-}" ]; then
  KC="$HOME/Library/Keychains/login.keychain-db"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KC"
  security set-keychain-settings -lut 7200 "$KC"
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KC" >/dev/null 2>&1 || true
fi

~/bin/xcodegen generate

xcodebuild archive \
  -project CircuitLens.xcodeproj \
  -scheme CircuitLens \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist exportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID"

echo "Upload succeeded! Check App Store Connect -> TestFlight."
rm -rf "$ARCHIVE" ~/Library/Developer/Xcode/Archives/* 2>/dev/null || true
