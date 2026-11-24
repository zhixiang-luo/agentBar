#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/agentbar-clang-cache}"
export SWIFT_DRIVER_CACHE_PATH="${SWIFT_DRIVER_CACHE_PATH:-/tmp/agentbar-swift-cache}"

PLUGIN_DIR="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
EXTRA_FLAGS=()
if [[ -d "$PLUGIN_DIR" ]]; then
  EXTRA_FLAGS=(-Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR")
fi

swift test --package-path "$ROOT_DIR" --disable-sandbox --cache-path /tmp/agentbar-spm-cache "${EXTRA_FLAGS[@]}"
