#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"

mkdir -p "$BUILD_DIR/clang-module-cache" \
  "$BUILD_DIR/swift-module-cache" \
  "$ROOT_DIR/.swiftpm/cache" \
  "$ROOT_DIR/.swiftpm/config" \
  "$ROOT_DIR/.swiftpm/security"

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/swift-module-cache"

swift run \
  --package-path "$ROOT_DIR" \
  --scratch-path "$BUILD_DIR" \
  --cache-path "$ROOT_DIR/.swiftpm/cache" \
  --config-path "$ROOT_DIR/.swiftpm/config" \
  --security-path "$ROOT_DIR/.swiftpm/security" \
  --disable-sandbox \
  ClipStackChecks
