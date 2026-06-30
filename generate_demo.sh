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

swift run slate-generator generate \
  --input SlateDemo/CloudKitMirrorDemo/Models \
  --output SlateDemo/CloudKitMirrorDemo/Generated \
  --schema-name CloudKitMirrorSchema \
  --model-module CloudKitMirrorDemo \
  --runtime-module CloudKitMirrorDemo \
  --prune

swift run slate-generator generate \
  --input SlateDemo/CloudKitShareDemo/Models \
  --output SlateDemo/CloudKitShareDemo/Generated \
  --schema-name CloudKitShareSchema \
  --model-module CloudKitShareDemo \
  --runtime-module CloudKitShareDemo \
  --prune