#!/bin/sh
# sichttest.sh — abgeschottete Testkopie „Knippi Sichttest“ bauen, signieren, starten.
#
# Eigene Kennung (dev.mwlr.knippi.sichttest), kein Update-Feed, Developer-ID-Signatur.
# Warum Developer ID: macOS bindet die Bildschirmaufnahme-Freigabe an die Signatur.
# Ad hoc signiert gilt sie nur für genau einen Build (gemessen 2026-11-20: nach dem
# Neubau wieder „Zugriff erforderlich“). Mit Developer ID sollte sie Neubauten
# überstehen — unbewiesen, nach dem Neubau im tccd-Log prüfen (auth_value=2).
#
# Aufruf:  sh scripts/sichttest.sh
#          CONFIG=Release sh scripts/sichttest.sh   (optimiert, z. B. für Tempo-Messungen)
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

CONFIG=${CONFIG:-Debug}
LOG=/tmp/knippi-sichttest-build.log
xcodegen generate >"$LOG" 2>&1
if ! xcodebuild -project Knippi.xcodeproj -scheme Knippi -configuration "$CONFIG" \
    -derivedDataPath build-dev CODE_SIGNING_ALLOWED=NO build >>"$LOG" 2>&1; then
    grep -E 'error:' "$LOG" | sort -u | head -8
    echo "✗ Build fehlgeschlagen — Log: $LOG" >&2
    exit 1
fi

IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "✗ Kein Developer-ID-Zertifikat im Schlüsselbund" >&2; exit 1; }

DEST="$HOME/Applications/Knippi Sichttest.app"
osascript -e 'quit app id "dev.mwlr.knippi.sichttest"' >/dev/null 2>&1 || true
sleep 1
if [ -e "$DEST" ]; then
    mv "$DEST" "$HOME/.Trash/knippi-sichttest-$(date +%s).app"
fi
mkdir -p "$HOME/Applications"
ditto "build-dev/Build/Products/$CONFIG/Knippi.app" "$DEST"

PLIST="$DEST/Contents/Info.plist"
# Eigenes URL-Schema: sonst kann knippi:// (z. B. vom Stream Deck) die Testkopie statt der
# echten App öffnen (Audit S6, gemessen 21.11. per lsregister).
/usr/libexec/PlistBuddy -c 'Set CFBundleIdentifier dev.mwlr.knippi.sichttest' \
    -c 'Set CFBundleName Knippi Sichttest' \
    -c 'Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 knippi-sichttest' "$PLIST"
/usr/libexec/PlistBuddy -c 'Delete SUFeedURL' "$PLIST" >/dev/null 2>&1 || true

codesign --force --deep --options runtime \
    --entitlements App/Entitlements/Knippi.entitlements \
    --sign "$IDENTITY" "$DEST"
codesign --verify --deep --strict "$DEST"

open "$DEST"
echo "✓ Knippi Sichttest läuft ($DEST)"
