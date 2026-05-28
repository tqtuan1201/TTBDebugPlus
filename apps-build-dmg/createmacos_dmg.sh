#!/usr/bin/env bash

set -euo pipefail

# Move to the directory where this script is located.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- CONFIGURATION ---
APP_NAME="TTBDebugPlus"
APP_FILE="macos/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-Installer.dmg"
VOL_NAME="TTBDebugPlus — Smart debugs"
README_FILE="README.txt"
HELP_URL="https://tqtuan1201.github.io/public/docs/ttbaseuikit/"
BACKGROUND_IMG="installer_background.png"
STAGING_DIR="./dist"
VERIFY_MOUNT_DIR="/private/tmp/${APP_NAME}-dmg-verify"
CREATE_DMG_SANDBOX_SAFE="${CREATE_DMG_SANDBOX_SAFE:-0}"

log() {
    printf '%s\n' "$1"
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

cleanup() {
    if [ -d "$VERIFY_MOUNT_DIR" ]; then
        hdiutil detach "$VERIFY_MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    fi
    rm -rf "$STAGING_DIR" "$VERIFY_MOUNT_DIR"
}

validate_inputs() {
    [ -d "$APP_FILE" ] || fail "Missing app bundle: $APP_FILE"
    [ -f "$BACKGROUND_IMG" ] || fail "Missing Finder background image: $BACKGROUND_IMG"
    command -v create-dmg >/dev/null 2>&1 || fail "Missing create-dmg. Install it with: brew install create-dmg"
    command -v hdiutil >/dev/null 2>&1 || fail "Missing hdiutil."
}

prepare_staging() {
    log "Preparing staging area..."
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"

    log "Copying ${APP_FILE}..."
    cp -R "$APP_FILE" "$STAGING_DIR/"

    log "Writing ${README_FILE}..."
    cat > "$STAGING_DIR/$README_FILE" <<EOF
--- TTBaseDebug Plus ---

INSTALLATION:
1. Drag the '${APP_NAME}' icon into the 'Applications' folder shortcut.
2. Open your Applications folder and launch the app.

DOCUMENTATION & SUPPORT:
${HELP_URL}
EOF
}

create_installer_dmg() {
    log "Creating ${DMG_NAME}..."
    rm -f "$DMG_NAME"
    rm -f "rw."*".${DMG_NAME}"

    run_create_dmg() {
        create-dmg \
        --volname "$VOL_NAME" \
        --background "$BACKGROUND_IMG" \
        --window-pos 200 120 \
        --window-size 800 400 \
        --icon-size 120 \
        --text-size 14 \
        --icon "${APP_NAME}.app" 200 220 \
        --app-drop-link 600 220 \
        --icon "$README_FILE" 400 310 \
        --hide-extension "${APP_NAME}.app" \
        --no-internet-enable \
        --hdiutil-retries 10 \
        --hdiutil-quiet \
        "$@" \
        "$DMG_NAME" \
        "$STAGING_DIR/"
    }

    if [ "$CREATE_DMG_SANDBOX_SAFE" = "1" ]; then
        log "Sandbox-safe mode enabled: Finder background layout AppleScript may be skipped by create-dmg."
        run_create_dmg --sandbox-safe
    else
        run_create_dmg
    fi
}

verify_dmg() {
    log "Verifying ${DMG_NAME} contents..."
    [ -f "$DMG_NAME" ] || fail "DMG was not created: $DMG_NAME"

    rm -rf "$VERIFY_MOUNT_DIR"
    mkdir -p "$VERIFY_MOUNT_DIR"
    hdiutil attach "$DMG_NAME" -readonly -nobrowse -mountpoint "$VERIFY_MOUNT_DIR" -quiet

    [ -d "$VERIFY_MOUNT_DIR/${APP_NAME}.app" ] || fail "DMG is missing ${APP_NAME}.app"
    [ -L "$VERIFY_MOUNT_DIR/Applications" ] || fail "DMG is missing Applications drop link"
    [ -f "$VERIFY_MOUNT_DIR/$README_FILE" ] || fail "DMG is missing $README_FILE"
    [ -f "$VERIFY_MOUNT_DIR/.background/$BACKGROUND_IMG" ] || fail "DMG is missing .background/$BACKGROUND_IMG"
    [ -f "$VERIFY_MOUNT_DIR/.DS_Store" ] || fail "DMG is missing .DS_Store Finder layout metadata"

    hdiutil detach "$VERIFY_MOUNT_DIR" -quiet
    rm -rf "$VERIFY_MOUNT_DIR"

    log "Verified: app, Applications link, README, Finder background image, and Finder layout metadata are present."
}

main() {
    trap cleanup EXIT

    log "---------------------------------------------------"
    log "Starting DMG build process..."
    log "---------------------------------------------------"

    validate_inputs
    prepare_staging
    create_installer_dmg
    verify_dmg

    log "---------------------------------------------------"
    log "SUCCESS: ${DMG_NAME} is ready."
    log "---------------------------------------------------"
}

main "$@"
