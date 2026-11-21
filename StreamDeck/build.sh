#!/bin/bash
# Builds the Stream Deck plugin as dist/streamdeck/Knippi.streamDeckPlugin (double-click installs it in Stream Deck).
#   sh StreamDeck/build.sh            → Apple-Silicon binary, Developer ID, hardened runtime, notarized
#   sh StreamDeck/build.sh --no-notary → same without notarization (local test only)
# Tastenbilder kommen aus dem Skill /streamdeck-glas (plugins.json, Eintrag „knippi“), Profile aus StreamDeck/profiles.py.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARIZE=1
[ "${1:-}" = "--no-notary" ] && NOTARIZE=0

SRC="StreamDeck/dev.mwlr.knippi.deck.sdPlugin"
OUT="dist/streamdeck"
# Own subfolder: generate_appcast scans dist/ for archives and must only see the app ZIP.
PKG="$OUT/Knippi.streamDeckPlugin"
DEVELOPER_ID="${DEVELOPER_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
[ -n "$DEVELOPER_ID" ] || { echo "✗ Kein 'Developer ID Application'-Zertifikat im Schlüsselbund"; exit 1; }

# Manifest version follows the app (four parts, Elgato format) – a plugin update needs a higher version.
APP_VERSION=$(awk -F'"' '/MARKETING_VERSION/ { print $2; exit }' project.yml)
[ -n "$APP_VERSION" ] || { echo "✗ MARKETING_VERSION nicht gefunden"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
ditto "$SRC" "$OUT/dev.mwlr.knippi.deck.sdPlugin"
python3 -I StreamDeck/profiles.py "$OUT/dev.mwlr.knippi.deck.sdPlugin/profiles" "${APP_VERSION}.0" >/dev/null
sed -i '' -E "s/(\"Version\": )\"[^\"]+\"/\1\"${APP_VERSION}.0\"/" "$OUT/dev.mwlr.knippi.deck.sdPlugin/manifest.json"
grep -q "\"Version\": \"${APP_VERSION}.0\"" "$OUT/dev.mwlr.knippi.deck.sdPlugin/manifest.json" || { echo "✗ Manifest-Version nicht gesetzt"; exit 1; }

BIN="$OUT/dev.mwlr.knippi.deck.sdPlugin/knippideck"
# Apple Silicon only, like Knippi itself (README → Voraussetzungen).
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos15.0 StreamDeck/Sources/main.swift -o "$BIN"
codesign --force --options runtime --timestamp -i dev.mwlr.knippi.deck --sign "$DEVELOPER_ID" "$BIN"
codesign --verify --strict "$BIN"

if [ "$NOTARIZE" = 1 ]; then
    NOTARY_PROFILE="${NOTARY_PROFILE:-}"
    if [ -z "$NOTARY_PROFILE" ]; then
        for candidate in knippi-notary notary tippi-notary kalli-notary; do
            if xcrun notarytool history --keychain-profile "$candidate" >/dev/null 2>&1; then NOTARY_PROFILE="$candidate"; break; fi
        done
    fi
    [ -n "$NOTARY_PROFILE" ] || { echo "✗ Kein notarytool-Profil gefunden"; exit 1; }
    ditto -c -k "$BIN" "$OUT/knippideck.zip"
    # A bare binary cannot be stapled; Gatekeeper asks Apple online the first time. So the verdict must be "Accepted".
    RESULT=$(xcrun notarytool submit "$OUT/knippideck.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json) \
        || { echo "$RESULT"; echo "✗ Notarisierung fehlgeschlagen"; exit 1; }
    rm "$OUT/knippideck.zip"
    STATUS=$(printf '%s' "$RESULT" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))')
    [ "$STATUS" = "Accepted" ] || { echo "$RESULT"; echo "✗ Notarisierung: $STATUS"; exit 1; }
    echo "  ✓ Plugin notarisiert"
fi

# .streamDeckPlugin = ZIP with the .sdPlugin folder at the top.
(cd "$OUT" && zip -qr -X Knippi.streamDeckPlugin dev.mwlr.knippi.deck.sdPlugin)
echo "✅ $PKG"
