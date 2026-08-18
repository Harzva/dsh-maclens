#!/bin/bash
# Build the MaclensBridge Swift binary and install it to ./bin/maclens
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_DIR="$ROOT/swift"
BIN_DIR="$ROOT/bin"

echo "Building MaclensBridge (Swift, release)..."
(cd "$SWIFT_DIR" && swift build -c release)

mkdir -p "$BIN_DIR"
cp "$SWIFT_DIR/.build/release/MaclensBridge" "$BIN_DIR/maclens"
echo "Installed: $BIN_DIR/maclens"
"$BIN_DIR/maclens" ocr --help >/dev/null 2>&1 || true
echo "Done."
