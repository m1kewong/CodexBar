#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ios/CodexBariOS.xcodeproj"
SCHEME="CodexBariOSApp"

pick_device_id() {
    local booted_id
    local fallback_id

    booted_id="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ && /Booted/{print $2; exit}')"
    if [[ -n "$booted_id" ]]; then
        echo "$booted_id"
        return 0
    fi

    fallback_id="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ && !/unavailable/{print $2; exit}')"
    echo "$fallback_id"
}

open_simulator_ui() {
    local device_id="$1"

    # Open and focus Simulator on the selected device so users can see the launched app.
    open -a Simulator --args -CurrentDeviceUDID "$device_id" >/dev/null 2>&1 || open -a Simulator >/dev/null 2>&1

    local attempt
    for attempt in {1..40}; do
        if pgrep -x Simulator >/dev/null 2>&1; then
            osascript -e 'tell application "Simulator" to activate' >/dev/null 2>&1 || true
            return 0
        fi
        sleep 0.25
    done

    echo "Failed to open Simulator app UI." >&2
    return 1
}

DEVICE_ID="$(pick_device_id)"
if [[ -z "$DEVICE_ID" ]]; then
    echo "No available iPhone simulator found." >&2
    exit 1
fi

open_simulator_ui "$DEVICE_ID"

xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "id=$DEVICE_ID" \
    build

APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -type d \
    -path "*/Build/Products/Debug-iphonesimulator/CodexBariOSApp.app" \
    -print \
    | head -n1)"

if [[ -z "$APP_PATH" ]]; then
    echo "Could not locate CodexBariOSApp.app in DerivedData." >&2
    exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"

xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"

open_simulator_ui "$DEVICE_ID"
