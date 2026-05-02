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

# The demo intentionally keeps immutable models and generated persistence code
# in one app module. The generator currently emits imports for split-module
# projects, so remove the app's self-import after generation.
perl -0pi -e 's/^import SlateDemo\n//mg' \
  SlateDemo/SlateDemo/Generated/Mutable/*.swift \
  SlateDemo/SlateDemo/Generated/Bridge/*.swift \
  SlateDemo/SlateDemo/Generated/Schema/*.swift

# Same-module bridge files refer to Core Data APIs like objectID and
# primitiveValue(forKey:) directly. Keep the bridge files explicit about that
# dependency until the generator handles this mode natively.
for file in SlateDemo/SlateDemo/Generated/Bridge/*.swift; do
  if ! grep -q '^@preconcurrency import CoreData$' "$file"; then
    perl -0pi -e 's/^import Foundation\n/@preconcurrency import CoreData\nimport Foundation\n/' "$file"
  fi
done
