#!/bin/sh
# Captures sanitized provider fixtures via TokenTankProbe (§9.4).
# The API key is read from stdin; run sanitize-fixtures.sh before committing.
#
# Usage: echo "$KEY" | scripts/make-fixture.sh mimo-sk|mimo-tp|deepseek|kimi-cn|kimi-intl|kimi-admin|kimi-coding [probe args]
# Extra args are forwarded (e.g. --tp-base https://token-plan-sgp.xiaomimimo.com).
set -e
cd "$(dirname "$0")/.."
MODE="${1:?usage: make-fixture.sh mimo-sk|mimo-tp|deepseek|kimi-cn|kimi-intl|kimi-admin|kimi-coding}"
shift
OUT="Packages/TokenTankKit/Tests/TokenTankKitTests/Fixtures"
DEST="platform=macOS,arch=arm64"
xcodebuild -scheme TokenTankProbe -destination "$DEST" build >/dev/null
BIN=$(xcodebuild -scheme TokenTankProbe -destination "$DEST" -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')
"$BIN/TokenTankProbe" "$MODE" --out "$OUT" "$@"
sh scripts/sanitize-fixtures.sh
