#!/bin/zsh
set -eu
task_root=$(cd "$(dirname "$0")/.." && pwd)
preview_dir=$(mktemp -d /tmp/aiquota-insight-preview.XXXXXX)
trap 'rm -rf "$preview_dir"' EXIT
swiftc -parse-as-library \
  "$task_root/Packages/AIQuotaKit/Sources/AIQuotaKit/Models/QuotaExhaustionForecast.swift" \
  "$task_root/Packages/AIQuotaKit/Sources/AIQuotaKit/Formatting/QuotaForecastTextFormatter.swift" \
  "$task_root/AIQuota/Views/MacQuotaInsightBanner.swift" \
  "$task_root/scripts/preview-quota-insight.swift" \
  -o "$preview_dir/QuotaInsightPreview"
"$preview_dir/QuotaInsightPreview" "$@"
