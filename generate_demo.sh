#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

swift run slate-generator generate \
  --input SlateDemo/SlateDemo/Models \
  --output SlateDemo/SlateDemo/Generated \
  --schema-name DemoSlateSchema \
  --model-module SlateDemo \
  --runtime-module SlateDemo \
  --prune
