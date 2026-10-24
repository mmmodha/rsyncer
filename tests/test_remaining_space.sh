#!/bin/bash

set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/external-disk-transfer.sh"

fixture="$(mktemp -d -t rsyncer-space.XXXXXX)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/source/Data" "$fixture/destination/Data"
printf 'already present\n' >"$fixture/source/Data/same.txt"
cp -p "$fixture/source/Data/same.txt" "$fixture/destination/Data/same.txt"
printf 'only this file still needs transferring\n' >"$fixture/source/Data/new.txt"

remaining_kb="$(remaining_transfer_kb "$fixture/destination" "$fixture/source/Data")"
if [[ "$remaining_kb" -ne 1 ]]; then
  printf 'FAIL: expected 1 KiB remaining, got %s KiB\n' "$remaining_kb" >&2
  exit 1
fi

printf 'Remaining-space test passed.\n'
