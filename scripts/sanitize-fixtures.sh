#!/bin/sh
# Masks secret-looking fragments in fixtures and fails on leftovers (§9.4, §10).
# Run in CI and after make-fixture.sh.
# NOTE: BSD `sed -i ''` — macOS-only by design, do not port to GNU syntax.
# Also review every new fixture by eye before committing (see §9.4).
set -e
cd "$(dirname "$0")/.."
FIX="Packages/TokenTankKit/Tests/TokenTankKitTests/Fixtures"
LC_ALL=C find "$FIX" -name '*.json' -exec sed -E -i '' \
    -e 's/Bearer [A-Za-z0-9._+/=-]*/Bearer ***/g' \
    -e 's/(sk|tp|sk-admin)-[A-Za-z0-9._+/=-]+/\1-***/g' {} +
if LC_ALL=C grep -rEn '(sk|tp|sk-admin)-[A-Za-z0-9]{8}|Bearer [A-Za-z0-9]{8}|Bearer \*\*\*[A-Za-z0-9+/=]' "$FIX"; then
    echo "sanitize-fixtures: unmasked secrets found" >&2
    exit 1
fi
echo "sanitize-fixtures: ok"
