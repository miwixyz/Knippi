#!/usr/bin/env bash
# release.sh — signiertes, notarisiertes Knippi-ZIP, GitHub-Release, signierter Appcast.
#
# Übernommen von Seam (scripts/release.sh, dort seit v0.1.0 erprobt), das es von
# Kalli hat. Die Prüfpunkte stammen aus echten Vorfällen bei Kalli, Tippi, Seam
# und MacStd; die Kommentare nennen jeweils den Grund.
#
# Developer-ID-Signatur ist bei Knippi wichtig: Die Bildschirmaufnahme-Freigabe
# hängt an Kennung + Team. Eine stabile Signatur heißt, macOS fragt einmal, auch
# nach Updates.
#
# Aufruf:
#   make release                 # bauen, notarisieren, veröffentlichen
#   PUBLISH=0 make release       # alles außer dem GitHub-Release (Probelauf)
#   SKIP_TESTS=1 PUBLISH=0 ...   # Probelauf ohne die mehrminütigen Tests
#
# Voraussetzungen auf dem Mac, der released:
#   - Developer-ID-Zertifikat im Schlüsselbund
#   - notarytool-Profil (gesucht: knippi-notary, notary, tippi-notary, kalli-notary)
#   - Sparkle-EdDSA-Schlüssel im Login-Schlüsselbund (derselbe wie Kalli/Tippi/Seam)

set -euo pipefail
cd "$(dirname "$0")/.."

APP="Knippi"
BUNDLE="${APP}.app"
REPO="miwixyz/Knippi"
TEAM="LTKJ6Z2VYB"
DIST="dist"
PUBLISH="${PUBLISH:-1}"
SKIP_TESTS="${SKIP_TESTS:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
# Das Repo hat zwei Remotes (origin = miwixyz/Knippi, upstream = lzhgus/Capso).
# Ohne feste Angabe könnte gh das Release oder das Aufräumen gegen Capso richten.
export GH_REPO="${REPO}"

# release.env ist optional, gitignoriert und enthält keine Geheimnisse — nur
# Variablenzuweisungen (DEVELOPER_ID, NOTARY_PROFILE). Zugangsdaten liegen im
# Schlüsselbund.
[ -f release.env ] && . ./release.env

RESUME_HINT=""
fail() {
    echo "✗ $*" >&2
    [ -z "${RESUME_HINT}" ] || echo "→ ${RESUME_HINT}" >&2
    exit 1
}
step() { echo ""; echo "▶ $*"; }

# Nur 0 oder 1: `[ "$PUBLISH" -eq 0 ]` war bei "no" ein Vergleichsfehler und
# veröffentlichte (Kalli-Audit K-S2, 2026-09-27).
case "${PUBLISH}" in 0|1) ;; *) fail "PUBLISH muss 0 oder 1 sein, ist aber '${PUBLISH}'" ;; esac
case "${SKIP_TESTS}" in 0|1) ;; *) fail "SKIP_TESTS muss 0 oder 1 sein, ist aber '${SKIP_TESTS}'" ;; esac
# Tests überspringen nur im Probelauf. Ein veröffentlichtes Release ohne Tests
# ist ein Release ohne Abnahme.
[ "${SKIP_TESTS}" = "1" ] && [ "${PUBLISH}" = "1" ] && fail "SKIP_TESTS=1 nur zusammen mit PUBLISH=0"

# ---------------------------------------------------------------------------
step "[0/10] Vorbedingungen"
# ---------------------------------------------------------------------------
command -v gh >/dev/null || fail "gh fehlt — brew install gh"
command -v xcodegen >/dev/null || fail "xcodegen fehlt — brew install xcodegen"

# `git status --porcelain` statt `git diff`: auch ungetrackte Dateien landen im
# Build (Kalli-Audit K-S3). Ignorierte Dateien (build/, dist/) zählen nicht.
[ -z "$(git status --porcelain)" ] \
    || fail "Arbeitsbaum ist nicht sauber (auch ungetrackte Dateien zählen). Erst committen, dann releasen."

# Der Feed (SUFeedURL) liest main. Ein Release von anderem Zweig oder
# ungepushtem Stand fände die App nie (Seam, Rafter-Fund F1).
if [ "${PUBLISH}" = "1" ]; then
    [ "$(git branch --show-current)" = "main" ] || fail "Nicht auf main — der Update-Feed liest main"
    git fetch -q origin main || fail "git fetch origin main fehlgeschlagen"
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
        || fail "HEAD ist nicht gleich origin/main. Erst pushen, dann releasen."
    # git push und die Tag-Prüfung hängen an origin, gh an GH_REPO: beide müssen dasselbe Repo sein (Audit S10).
    case "$(git remote get-url origin)" in
        *github.com[:/]"${REPO}".git|*github.com[:/]"${REPO}") ;;
        *) fail "origin zeigt nicht auf ${REPO}" ;;
    esac
fi

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)"
[ -n "${VERSION}" ] || fail "MARKETING_VERSION nicht in project.yml gefunden"
TAG="v${VERSION}"

git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null \
    && fail "Tag ${TAG} existiert schon lokal. Version in project.yml anheben (oder ein alter Capso-Tag: git tag -d ${TAG}; upstream holt seit 20.11. keine Tags mehr)."
# Auch am Remote fragen: ein dort vorhandener Tag ließe Schritt 8 erst nach der Notarisierung scheitern.
git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1 \
    && fail "Tag ${TAG} existiert schon auf GitHub. Version in project.yml anheben."
grep -q "^## \[${VERSION}\]" CHANGELOG.md || fail "CHANGELOG hat keinen Abschnitt ## [${VERSION}]"
# Das Datum im Abschnitt muss der Release-Tag sein, sonst steht in Release-Notizen und
# Update-Fenster ein falscher Tag (0.1.0 wurde vorab datiert). Nur beim Veröffentlichen.
if [ "${PUBLISH}" = "1" ]; then
    TODAY="$(date +%F)"
    grep -qF "## [${VERSION}] — ${TODAY}" CHANGELOG.md \
        || fail "CHANGELOG-Abschnitt [${VERSION}] trägt nicht das heutige Datum (${TODAY}). Zeile anpassen: ## [${VERSION}] — ${TODAY}"
fi

# Info.plist: Feed und Schlüssel prüfen, bevor gebaut wird. Ohne
# SURequireSignedFeed nähme die App auch einen manipulierten Appcast an.
PLIST="App/Resources/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' "${PLIST}" 2>/dev/null)" = "https://raw.githubusercontent.com/${REPO}/main/appcast.xml" ] \
    || fail "SUFeedURL in ${PLIST} zeigt nicht auf ${REPO}/main/appcast.xml"
[ "$(/usr/libexec/PlistBuddy -c 'Print SURequireSignedFeed' "${PLIST}" 2>/dev/null)" = "true" ] \
    || fail "SURequireSignedFeed fehlt in ${PLIST}"
# Sparkle 2 verlangt beide Schalter zusammen, sonst bricht der Updater beim Start mit
# „Fatal updater error (5)“ ab und die App sucht nie wieder nach Updates (Knippi 0.1.0).
[ "$(/usr/libexec/PlistBuddy -c 'Print SUVerifyUpdateBeforeExtraction' "${PLIST}" 2>/dev/null)" = "true" ] \
    || fail "SUVerifyUpdateBeforeExtraction fehlt in ${PLIST} (Pflicht zusammen mit SURequireSignedFeed)"
/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "${PLIST}" >/dev/null 2>&1 || fail "SUPublicEDKey fehlt in ${PLIST}"

# Zertifikat prüfen statt voraussetzen: sonst signiert xcodebuild still ad hoc.
DEVELOPER_ID="${DEVELOPER_ID:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
[ -n "${DEVELOPER_ID}" ] || fail "Kein 'Developer ID Application'-Zertifikat im Schlüsselbund"

if [ -n "${NOTARY_PROFILE}" ]; then
    xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1 \
        || fail "notarytool-Profil '${NOTARY_PROFILE}' antwortet nicht. Anlegen: xcrun notarytool store-credentials"
else
    for candidate in knippi-notary notary tippi-notary kalli-notary; do
        if xcrun notarytool history --keychain-profile "${candidate}" >/dev/null 2>&1; then
            NOTARY_PROFILE="${candidate}"
            break
        fi
    done
    [ -n "${NOTARY_PROFILE}" ] || fail "Kein notarytool-Profil gefunden (gesucht: knippi-notary, notary, tippi-notary, kalli-notary). Anlegen: xcrun notarytool store-credentials"
fi

echo "  ✓ Version ${VERSION} · Tag ${TAG} frei · Baum sauber"
echo "  ✓ Zertifikat: ${DEVELOPER_ID}"
echo "  ✓ notarytool-Profil: ${NOTARY_PROFILE}"

# ---------------------------------------------------------------------------
step "[1/10] Tests (alle Paket-Suiten + App, dauert mehrere Minuten)"
# ---------------------------------------------------------------------------
if [ "${SKIP_TESTS}" = "1" ]; then
    echo "  ⚠️  übersprungen (SKIP_TESTS=1, nur Probelauf)"
else
    sh scripts/test-all.sh > /tmp/knippi-release-tests.log 2>&1 \
        || fail "Tests fehlgeschlagen. Log: /tmp/knippi-release-tests.log"
    echo "  ✓ alle Tests bestanden"
fi

# ---------------------------------------------------------------------------
# Bauen: archive + exportArchive, NICHT `build`. Lehre aus Tippi v2.3.0: Nur der
# Export-Pfad bettet das richtige Provisioning-Profil ein; ohne killt amfid eine
# App mit Berechtigungen beim Start (-413).
# ---------------------------------------------------------------------------
BUILD_NUMBER="$(git rev-list --count HEAD)"
step "[2/10] Release-Build, Hardened Runtime (Build ${BUILD_NUMBER})"

for old in build/${APP}.xcarchive build/export "${DIST}"; do
    [ -e "$old" ] && mv "$old" "$(mktemp -d /tmp/knippi-old.XXXXXX)/"
done
mkdir -p "${DIST}"
xcodegen generate >/dev/null

xcodebuild \
    -project "${APP}.xcodeproj" \
    -scheme "${APP}" \
    -configuration Release \
    -derivedDataPath ./build \
    -archivePath "./build/${APP}.xcarchive" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    -allowProvisioningUpdates \
    archive > /tmp/knippi-release-build.log 2>&1 \
    || fail "Archivieren fehlgeschlagen. Log: /tmp/knippi-release-build.log"

xcodebuild -exportArchive \
    -archivePath "./build/${APP}.xcarchive" \
    -exportPath ./build/export \
    -exportOptionsPlist scripts/exportOptions-developer-id.plist \
    -allowProvisioningUpdates >> /tmp/knippi-release-build.log 2>&1 \
    || fail "Export fehlgeschlagen. Log: /tmp/knippi-release-build.log"

APP_PATH="build/export/${BUNDLE}"
[ -d "${APP_PATH}" ] || fail "Export hat kein ${BUNDLE} erzeugt"

# ---------------------------------------------------------------------------
step "[3/10] Signatur und Inhalt prüfen"
# ---------------------------------------------------------------------------
SIGN_INFO="$(codesign -dv --verbose=4 "${APP_PATH}" 2>&1)"
echo "${SIGN_INFO}" | grep -q "Authority=Developer ID Application" || fail "Nicht mit Developer ID signiert"
echo "${SIGN_INFO}" | grep -q "flags=.*runtime" || fail "Hardened Runtime fehlt"
echo "${SIGN_INFO}" | grep -q "TeamIdentifier=${TEAM}" || fail "Falsches Team in der Signatur (erwartet ${TEAM})"
echo "${SIGN_INFO}" | grep -q "Identifier=dev.mwlr.knippi$" || fail "Falsche Kennung (erwartet dev.mwlr.knippi)"
codesign --verify --deep --strict "${APP_PATH}" || fail "Signatur ungültig (--deep --strict)"

# Berechtigungen: genau die aus App/Entitlements/Knippi.entitlements
# (Netz für Updates, Mikrofon und Kamera für Bildschirmvideos ab 0.3.0). Jede
# weitere (z. B. disable-library-validation) erlaubte Code-Einschleusung samt
# Bildschirmaufnahme-Freigabe. Exit-Code von codesign getrennt prüfen: ein
# scheiterndes codesign lieferte sonst leer (Seam-Audit 18.11.).
ENTS_XML="$(codesign -d --entitlements - --xml "${APP_PATH}" 2>/dev/null)" || fail "Berechtigungen nicht lesbar (codesign)"
ENTS="$(printf '%s' "${ENTS_XML}" | grep -o '<key>[^<]*</key>' | sed 's/<[^>]*>//g' | sort | tr '\n' ' ')"
EXPECTED="com.apple.security.device.audio-input com.apple.security.device.camera com.apple.security.network.client "
[ "${ENTS}" = "${EXPECTED}" ] || fail "Berechtigungen weichen ab: '${ENTS}' (erwartet: '${EXPECTED}')"

# Die gebaute App muss die Version tragen, die veröffentlicht wird, und den
# signierten Feed verlangen.
BUILT_PLIST="${APP_PATH}/Contents/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${BUILT_PLIST}")" = "${VERSION}" ] \
    || fail "Gebaute App trägt nicht Version ${VERSION}"
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "${BUILT_PLIST}")" = "${BUILD_NUMBER}" ] \
    || fail "Gebaute App trägt nicht Build ${BUILD_NUMBER}"
[ "$(/usr/libexec/PlistBuddy -c 'Print SURequireSignedFeed' "${BUILT_PLIST}")" = "true" ] \
    || fail "Gebaute App verlangt keinen signierten Feed"
[ "$(/usr/libexec/PlistBuddy -c 'Print SUVerifyUpdateBeforeExtraction' "${BUILT_PLIST}" 2>/dev/null)" = "true" ] \
    || fail "Gebaute App ohne SUVerifyUpdateBeforeExtraction, Sparkle würde mit Fatal error 5 abbrechen"
echo "  ✓ Developer ID (Team ${TEAM}) + Hardened Runtime, Berechtigungen wie erwartet, Version ${VERSION} (${BUILD_NUMBER})"

# ---------------------------------------------------------------------------
# Notarisiert wird ein ZIP, geheftet wird an die .app.
# ---------------------------------------------------------------------------
step "[4/10] Bei Apple einreichen (dauert meist 1–5 Minuten)"
ditto -c -k --keepParent "${APP_PATH}" "${DIST}/notarize.zip"
xcrun notarytool submit "${DIST}/notarize.zip" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait \
    --output-format json > "${DIST}/notarization.json"
STATUS="$(/usr/bin/plutil -extract status raw -o - "${DIST}/notarization.json")"
if [ "${STATUS}" != "Accepted" ]; then
    cat "${DIST}/notarization.json"
    fail "Notarisierung: ${STATUS} (Details: xcrun notarytool log <id> --keychain-profile ${NOTARY_PROFILE})"
fi
echo "  ✓ Notarisierung angenommen"

# ---------------------------------------------------------------------------
step "[5/10] Ticket anheften, Gatekeeper fragen"
# ---------------------------------------------------------------------------
xcrun stapler staple "${APP_PATH}" >/dev/null
xcrun stapler validate "${APP_PATH}" >/dev/null || fail "Ticket ist nicht angeheftet"
SPCTL="$(spctl --assess --type execute -vv "${APP_PATH}" 2>&1 || true)"
echo "${SPCTL}" | grep -q "accepted" || { echo "${SPCTL}"; fail "Gatekeeper lehnt die App ab"; }
echo "  ✓ Gatekeeper akzeptiert"

# ---------------------------------------------------------------------------
step "[6/10] ZIP packen und ALS AUSGELIEFERTES ARTEFAKT prüfen"
# ---------------------------------------------------------------------------
ZIP="${DIST}/${APP}-${VERSION}.zip"
# --norsrc --noextattr: sonst landen ._-Dateien im ZIP, und wer mit unzip
# entpackt, bekommt „beschädigt“ (MacStd 1.3.2, 2026-11-17).
ditto -c -k --norsrc --noextattr --keepParent "${APP_PATH}" "${ZIP}"
[ "$(unzip -l "${ZIP}" | grep -cE '/\._|__MACOSX' || true)" = 0 ] || fail "ZIP enthält ._-/__MACOSX-Einträge"
rm -f "${DIST}/notarize.zip"

# Wie ein Browser-Download: Quarantäne, mit unzip (nicht ditto) entpacken,
# Siegel, Ticket und Gatekeeper prüfen. Danach dasselbe mit ditto (Sparkle-Weg).
for method in unzip ditto; do
    V="$(mktemp -d)"
    cp "${ZIP}" "$V/q.zip"
    xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Browser;" "$V/q.zip"
    if [ "${method}" = unzip ]; then (cd "$V" && unzip -q q.zip) || fail "ZIP lässt sich mit unzip nicht entpacken"
    else ditto -x -k "$V/q.zip" "$V/" || fail "ZIP lässt sich mit ditto nicht entpacken"; fi
    [ -d "$V/${BUNDLE}" ] || fail "ZIP enthält kein ${BUNDLE}"
    codesign --verify --deep --strict "$V/${BUNDLE}" 2>/dev/null || fail "Signatur nach ${method} ungültig („beschädigt“ beim Nutzer)"
    xcrun stapler validate "$V/${BUNDLE}" >/dev/null || fail "Kein Notarisierungs-Ticket im ausgelieferten ZIP (${method})"
    spctl --assess --type execute "$V/${BUNDLE}" 2>/dev/null || fail "Gatekeeper lehnt das mit ${method} entpackte ZIP ab"
    mv "$V" "$(mktemp -d /tmp/knippi-verify.XXXXXX)/"
done
echo "  ✓ ${ZIP} ($(du -h "${ZIP}" | cut -f1)), mit unzip und ditto geprüft"

# Stream-Deck-Plugin: eigene Release-Datei (README → Stream Deck), notarisiert, Version = App.
DECK_PKG="${DIST}/streamdeck/Knippi.streamDeckPlugin"
DEVELOPER_ID="${DEVELOPER_ID}" NOTARY_PROFILE="${NOTARY_PROFILE}" sh StreamDeck/build.sh \
    || fail "Stream-Deck-Plugin nicht gebaut"
DECK_ABS="${PWD}/${DECK_PKG}"
V="$(mktemp -d)"
(cd "$V" && unzip -q "${DECK_ABS}") || fail "Stream-Deck-Paket lässt sich nicht entpacken"
codesign --verify --strict "$V/dev.mwlr.knippi.deck.sdPlugin/knippideck" 2>/dev/null || fail "Plugin-Signatur im Paket ungültig"
grep -q "\"Version\": \"${VERSION}.0\"" "$V/dev.mwlr.knippi.deck.sdPlugin/manifest.json" || fail "Plugin-Manifest nennt nicht ${VERSION}.0"
[ "$(ls "$V/dev.mwlr.knippi.deck.sdPlugin/profiles" | wc -l | tr -d ' ')" = 3 ] || fail "Plugin-Paket ohne die drei Profile"
mv "$V" "$(mktemp -d /tmp/knippi-verify.XXXXXX)/"
echo "  ✓ ${DECK_PKG} ($(du -h "${DECK_PKG}" | cut -f1)), Signatur, Version, Profile geprüft"

if [ "${PUBLISH}" = "0" ]; then
    echo ""
    echo "🛑 PUBLISH=0 — kein GitHub-Release, kein Appcast. Artefakte: ${ZIP}, ${DECK_PKG}"
    exit 0
fi

# ---------------------------------------------------------------------------
# Appcast VOR Tag und Release erzeugen und prüfen (Seam-Audit 18.11.: scheitert
# er danach, steht ein Release ohne Appcast online). Veröffentlicht wird er erst
# nach dem Release. Kein 2>/dev/null: ein still unsignierter Appcast heißt
# „niemand kann updaten“.
# ---------------------------------------------------------------------------
step "[7/10] Appcast erzeugen und signieren"
SPARKLE_BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
[ -x "${SPARKLE_BIN}/generate_appcast" ] || fail "generate_appcast fehlt unter ${SPARKLE_BIN}"
# sign_update --verify prüft nur gegen den Schlüssel im Schlüsselbund. Passt der nicht zum
# Schlüssel, den die ausgelieferte App kennt, wäre alles grün und niemand könnte updaten
# (Audit S1, 21.11.).
KEYCHAIN_EDKEY="$("${SPARKLE_BIN}/generate_keys" -p 2>/dev/null | tail -1)"
APP_EDKEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "${APP_PATH}/Contents/Info.plist" 2>/dev/null)"
[ -n "${KEYCHAIN_EDKEY}" ] && [ "${KEYCHAIN_EDKEY}" = "${APP_EDKEY}" ] \
    || fail "Sparkle-Schlüssel im Schlüsselbund passt nicht zu SUPublicEDKey der App. ZU TUN: auf diesem Mac den Familien-Schlüssel importieren (generate_keys -f)"

python3 -I scripts/release-notes.py "${VERSION}" CHANGELOG.md "${ZIP%.zip}.html" \
    || fail "Versionshinweise für ${VERSION} nicht erzeugt"
"${SPARKLE_BIN}/generate_appcast" "${DIST}" \
    --download-url-prefix "https://github.com/${REPO}/releases/download/${TAG}/" \
    --embed-release-notes \
    --link "https://github.com/${REPO}" \
    -o appcast.xml \
    || fail "generate_appcast fehlgeschlagen"
RESUME_HINT="ZU TUN vor dem Neuanlauf: git checkout -- appcast.xml 2>/dev/null || rm appcast.xml (noch nichts veröffentlicht)"

# Geparst mit Python, nicht grep (grep ist auf diesem Mac ugrep).
python3 -I - "$VERSION" "$TAG" "$BUILD_NUMBER" <<'PY' || fail "Appcast-Prüfung fehlgeschlagen"
import re, sys
version, tag, build = sys.argv[1:4]
xml = open("appcast.xml", encoding="utf-8").read()
m = re.search(r'sparkle:edSignature="([^"]+)"', xml)
if not m: sys.exit("Der Appcast trägt keine EdDSA-Signatur")
if f"<sparkle:shortVersionString>{version}<" not in xml: sys.exit(f"Der Appcast nennt Version {version} nicht")
if f"<sparkle:version>{build}<" not in xml: sys.exit(f"Der Appcast nennt Build {build} nicht")
if f"releases/download/{tag}/" not in xml: sys.exit(f"Die Download-URL zeigt nicht auf {tag}")
open(".appcast-sig", "w").write(m.group(1))
PY
APPCAST_SIG="$(cat .appcast-sig)"; rm -f .appcast-sig
# Passt die Signatur im Appcast zum Archiv, das ausgeliefert wird?
"${SPARKLE_BIN}/sign_update" --verify "${ZIP}" "${APPCAST_SIG}" \
    || fail "Die Signatur im Appcast passt NICHT zum ausgelieferten Archiv"
# Feed-Signatur: Die App verlangt sie (SURequireSignedFeed).
"${SPARKLE_BIN}/sign_update" --verify appcast.xml \
    || fail "Der Appcast trägt keine gültige Feed-Signatur, Knippi würde ihn ablehnen"
echo "  ✓ Archiv- und Feed-Signatur verifiziert"

# ---------------------------------------------------------------------------
step "[8/10] GitHub-Release ${TAG}"
# ---------------------------------------------------------------------------
awk -v v="[${VERSION}]" '
    index($0, "## " v) == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' CHANGELOG.md > "${DIST}/notes.md"
[ -s "${DIST}/notes.md" ] || fail "Keine Release-Notizen für ${VERSION} aus dem CHANGELOG gelesen"

# Tests und Notarisierung dauern Minuten: hat sich main inzwischen bewegt, scheitert sonst
# erst der Appcast-Push nach dem Release (Audit S3).
git fetch -q origin main || fail "git fetch origin main fehlgeschlagen"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
    || fail "origin/main hat sich während des Laufs bewegt – nichts veröffentlicht. ZU TUN: appcast.xml zurücksetzen, git pull --rebase, neu releasen"

git tag -a "${TAG}" -m "${APP} ${VERSION}"
RESUME_HINT="Tag ${TAG} lokal angelegt. ZU TUN vor dem Neuanlauf: git tag -d ${TAG}; appcast.xml zurücksetzen"
git push origin "${TAG}" || fail "Tag ${TAG} nicht gepusht"
RESUME_HINT="Tag ${TAG} gepusht, Release fehlt. ZU TUN: gh release create ${TAG} ${ZIP} ${DECK_PKG} --title \"${APP} ${VERSION}\" --notes-file ${DIST}/notes.md, danach appcast.xml committen + pushen"
gh release create "${TAG}" "${ZIP}" "${DECK_PKG}" --verify-tag --title "${APP} ${VERSION}" --notes-file "${DIST}/notes.md" \
    || fail "GitHub-Release ${TAG} nicht angelegt"
RESUME_HINT="Release ${TAG} online, Appcast noch nicht. ZU TUN: git add appcast.xml && git commit -m \"Appcast für ${TAG}\" && git push origin main"

# ---------------------------------------------------------------------------
step "[9/10] Am Remote prüfen, Appcast veröffentlichen"
# ---------------------------------------------------------------------------
ASSET="$(gh release view "${TAG}" --json assets --jq '.assets[].name' 2>/dev/null | LC_ALL=C sort | tr '\n' ' ' || true)"
[ "${ASSET}" = "${APP}-${VERSION}.zip Knippi.streamDeckPlugin " ] || fail "Release ${TAG} hat auf GitHub nicht die erwarteten Dateien (gefunden: '${ASSET}')"
echo "  ✓ ${TAG} veröffentlicht, Dateien: ${ASSET}"

# Der Appcast liegt im Repo: jede Änderung ist ein öffentlicher, datierter Commit.
git add appcast.xml
if git diff --cached --quiet -- appcast.xml; then
    echo "  ℹ️  Appcast unverändert"
else
    git commit -q -m "Appcast für ${TAG}"
    git push -q origin main || fail "Appcast committet, Push fehlgeschlagen. ZU TUN: git pull --rebase origin main && git push origin main"
    echo "  ✓ appcast.xml committet und gepusht"
fi
RESUME_HINT=""

FEED="https://raw.githubusercontent.com/${REPO}/main/appcast.xml"
if curl -fsS --netrc-file /dev/null "${FEED}" 2>/dev/null | grep -q "${VERSION}"; then
    echo "  ✓ Feed nennt ${VERSION}"
else
    echo "  ⚠️  Feed nennt ${VERSION} noch nicht — raw.githubusercontent cacht bis zu 5 Min."
    echo "     → ZU TUN: in ein paar Minuten prüfen: curl -s ${FEED} | grep ${VERSION}"
fi

# ---------------------------------------------------------------------------
step "[10/10] Alte Releases aufräumen (Hausregel: höchstens 5)"
# ---------------------------------------------------------------------------
# Löscht nur Releases, nie Tags, und nie eins, auf das der Appcast noch zeigt.
bash scripts/prune-releases.sh || echo "  ⚠️  Aufräumen fehlgeschlagen — Releases bleiben wie sie sind. → ZU TUN: bash scripts/prune-releases.sh --dry-run ansehen"

echo ""
echo "✅ ${APP} ${VERSION} released."
echo "→ Installieren auf einem anderen Mac: gh release download ${TAG} --repo ${REPO} --pattern '*.zip'"
echo "  ditto -x -k ${APP}-${VERSION}.zip . && mv ${BUNDLE} /Applications/"
