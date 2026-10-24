#!/bin/bash

set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/external-disk-transfer.sh"

for name in .Spotlight-V100 .Trashes .fseventsd .TemporaryItems .DocumentRevisions-V100; do
  if is_transferable_item "/Volumes/Source/$name"; then
    printf 'FAIL: macOS housekeeping item should be excluded: %s\n' "$name" >&2
    exit 1
  fi
done

for name in Documents Photos .important-user-data; do
  if ! is_transferable_item "/Volumes/Source/$name"; then
    printf 'FAIL: user item should remain transferable: %s\n' "$name" >&2
    exit 1
  fi
done

printf 'System-item filtering test passed.\n'
