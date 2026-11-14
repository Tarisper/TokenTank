#!/bin/sh
# Regenerates visual test references (not committed; see Tests/VisualTests/README.md).
set -e
cd "$(dirname "$0")/.."
TEST_RUNNER_VISUAL_TESTS_GENERATE=1 xcodebuild test \
    -scheme TokenTank \
    -destination 'platform=macOS' \
    -only-testing:VisualTests
