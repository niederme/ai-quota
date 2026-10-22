#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d /tmp/aiquota-menubar-test.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT

# Compile the production renderer and label without starting account/network code.
swiftc -module-cache-path "$test_dir/cache" -emit-library -emit-module \
  -module-name AIQuotaKit \
  "$repo_root/Packages/AIQuotaKit/Sources/AIQuotaKit/Drawing/GaugeImageMaker.swift" \
  -o "$test_dir/libAIQuotaKit.dylib" -emit-module-path "$test_dir/AIQuotaKit.swiftmodule"
swiftc -module-cache-path "$test_dir/cache" -I "$test_dir" -L "$test_dir" \
  -lAIQuotaKit -Xlinker -rpath -Xlinker "$test_dir" \
  "$repo_root/AIQuota/Views/MenuBarIconView.swift" \
  "$repo_root/scripts/tests/MenuBarIconRegression.swift" -o "$test_dir/regression"
"$test_dir/regression" --legacy
"$test_dir/regression"
