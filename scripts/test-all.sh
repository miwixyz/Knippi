#!/bin/sh
# Runs every test in the repo: `swift test` in each Packages/* package, then the
# app test target (KnippiTests) via xcodebuild. Takes several minutes.
#
# KnippiTests/RecordingSelectionModeTests is skipped: it drives the real
# recording selection overlay and can hang the whole xcodebuild run.
#
# Exit code is non-zero if any package or the app tests failed.
set -eu

cd "$(dirname "$0")/.."
root=$(pwd)
tmp=${TMPDIR:-/tmp}
tmp=${tmp%/}
failed=""

for pkg in Packages/*/; do
    pkg=${pkg%/}
    name=$(basename "$pkg")
    [ -f "$pkg/Package.swift" ] || continue
    log="$tmp/knippi-test-$name.log"
    if (cd "$pkg" && swift test >"$log" 2>&1); then
        status="ok"
    else
        status="FAILED"
        failed="$failed $name"
    fi
    summary=$(grep -E "Test run with|Executed [0-9]+ tests" "$log" | tail -n 1 || true)
    echo "$name: $status ${summary:-(no summary, see $log)}"
done

app_log="$tmp/knippi-test-app.log"
echo "App: xcodegen + xcodebuild test (log: $app_log)"
xcodegen generate >/dev/null
if xcodebuild -project "$root/Knippi.xcodeproj" -scheme Knippi -configuration Debug \
    -derivedDataPath "$root/build-dev" CODE_SIGNING_ALLOWED=NO test \
    -skip-testing:KnippiTests/RecordingSelectionModeTests >"$app_log" 2>&1; then
    :
else
    failed="$failed App"
fi
grep -E "Executed [0-9]+ tests|Test run with" "$app_log" | tail -n 1 || true
grep -E "\*\* TEST (SUCCEEDED|FAILED) \*\*" "$app_log" | tail -n 1 || echo "TEST FAILED (no result line, see $app_log)"

if [ -n "$failed" ]; then
    echo "FAILED:$failed"
    exit 1
fi
echo "All tests passed."
