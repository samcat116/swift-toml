#!/usr/bin/env bash
#
# Run the toml-test conformance suite (https://github.com/toml-lang/toml-test)
# against the decoder in Sources/TomlTestDecoder.
#
# Usage:
#   Scripts/toml-test.sh            # TOML 1.1.0, the version this library targets
#   Scripts/toml-test.sh 1.0.0      # TOML 1.0.0, minus the constructs 1.1.0 added
#
# Requires Go, which is used only to build the test runner; the runner carries
# the test files with it.

set -euo pipefail

TOML_VERSION="${1:-1.1.0}"
# Pinned so that a new release of the suite cannot turn a green build red
# without a commit here saying so.
TOML_TEST_VERSION="v1.6.0"

cd "$(dirname "$0")/.."
BUILD_DIR="$PWD/.build"
TOML_TEST="$BUILD_DIR/toml-test/bin/toml-test"

if [ ! -x "$TOML_TEST" ]; then
    if ! command -v go >/dev/null 2>&1; then
        echo "toml-test needs Go to build. Install Go, or fetch a toml-test" >&2
        echo "release binary and put it at $TOML_TEST" >&2
        exit 1
    fi
    echo "Building toml-test $TOML_TEST_VERSION..."
    GOBIN="$BUILD_DIR/toml-test/bin" \
        go install "github.com/toml-lang/toml-test/cmd/toml-test@$TOML_TEST_VERSION"
fi

swift build --target TomlTestDecoder

SKIP=()
if [ "$TOML_VERSION" = "1.0.0" ]; then
    # This library implements TOML 1.1.0, which made these constructs legal.
    # Under the 1.0.0 suite they are still listed as documents a parser must
    # reject, so accepting them is correct behaviour reported as a failure.
    SKIP=(
        -skip 'invalid/datetime/no-secs'
        -skip 'invalid/local-datetime/no-secs'
        -skip 'invalid/local-time/no-secs'
        -skip 'invalid/inline-table/linebreak-1'
        -skip 'invalid/inline-table/linebreak-2'
        -skip 'invalid/inline-table/linebreak-3'
        -skip 'invalid/inline-table/linebreak-4'
        -skip 'invalid/inline-table/trailing-comma'
        -skip 'invalid/string/basic-byte-escapes'
    )
fi

exec "$TOML_TEST" -toml "$TOML_VERSION" ${SKIP[@]+"${SKIP[@]}"} .build/debug/TomlTestDecoder
