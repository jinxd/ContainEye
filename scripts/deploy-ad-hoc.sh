#!/usr/bin/env bash
set -euo pipefail

# Configurable via environment variables.
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_NAME="${PROJECT_NAME:-ContainEye}"
SCHEME="${SCHEME:-ContainEye}"
CONFIGURATION="${CONFIGURATION:-Release}"
TEAM_ID="${TEAM_ID:-X5933694SW}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.nagel.ContainEye}"
WIDGET_BUNDLE_ID="${WIDGET_BUNDLE_ID:-com.nagel.ContainEye.TestsWidget}"
APP_PROFILE_NAME="${APP_PROFILE_NAME:-ContainEye ad hoc}"
WIDGET_PROFILE_NAME="${WIDGET_PROFILE_NAME:-ContainEye Widget ad hoc}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_DIR/build}"
EXPORT_DIR="${EXPORT_DIR:-$BUILD_DIR/ad-hoc-export}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_DIR/${PROJECT_NAME}.xcarchive}"
REMOTE_SSH="${REMOTE_SSH:-hannesnagel.com}"
REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-/root/files}"
REMOTE_SUBDIR="${REMOTE_SUBDIR:-containeye-ad-hoc}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://files.hannesnagel.com}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found" >&2
  exit 1
fi
if ! command -v ssh >/dev/null 2>&1 || ! command -v scp >/dev/null 2>&1; then
  echo "ssh/scp not found" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR" "$EXPORT_DIR"

cat > "$BUILD_DIR/ExportOptionsReleaseTesting.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>release-testing</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${APP_BUNDLE_ID}</key>
    <string>${APP_PROFILE_NAME}</string>
    <key>${WIDGET_BUNDLE_ID}</key>
    <string>${WIDGET_PROFILE_NAME}</string>
  </dict>
  <key>destination</key>
  <string>export</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>compileBitcode</key>
  <false/>
</dict>
</plist>
PLIST

echo "==> Archiving ${SCHEME}"
xcodebuild \
  -project "$PROJECT_DIR/${PROJECT_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive

echo "==> Exporting ad hoc IPA"
rm -rf "$EXPORT_DIR"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptionsReleaseTesting.plist"

IPA_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' | head -n 1)"
if [[ -z "$IPA_PATH" ]]; then
  echo "No IPA found in $EXPORT_DIR" >&2
  exit 1
fi
IPA_NAME="$(basename "$IPA_PATH")"

APP_INFO_PLIST="$ARCHIVE_PATH/Products/Applications/${PROJECT_NAME}.app/Info.plist"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_INFO_PLIST")"
DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_INFO_PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$APP_INFO_PLIST")"

MANIFEST_PATH="$EXPORT_DIR/manifest.plist"
cat > "$MANIFEST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key>
          <string>software-package</string>
          <key>url</key>
          <string>${PUBLIC_BASE_URL}/${REMOTE_SUBDIR}/${IPA_NAME}</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key>
        <string>${APP_BUNDLE_ID}</string>
        <key>bundle-version</key>
        <string>${BUNDLE_VERSION}</string>
        <key>kind</key>
        <string>software</string>
        <key>title</key>
        <string>${DISPLAY_NAME}</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "==> Uploading to ${REMOTE_SSH}:${REMOTE_BASE_DIR}/${REMOTE_SUBDIR}"
ssh "$REMOTE_SSH" "mkdir -p '$REMOTE_BASE_DIR/$REMOTE_SUBDIR'"
scp "$IPA_PATH" "$MANIFEST_PATH" "$REMOTE_SSH:$REMOTE_BASE_DIR/$REMOTE_SUBDIR/"

echo "==> Ensuring Nginx file server is running on :8006"
ssh "$REMOTE_SSH" "cd '$REMOTE_BASE_DIR' && docker compose up -d web"

MANIFEST_URL="${PUBLIC_BASE_URL}/${REMOTE_SUBDIR}/manifest.plist"
INSTALL_URL="itms-services://?action=download-manifest&url=${MANIFEST_URL}"

echo
echo "Manifest URL: $MANIFEST_URL"
echo "Install URL:  $INSTALL_URL"
