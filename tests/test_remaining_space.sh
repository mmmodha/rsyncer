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

set +e
error_output="$(remaining_transfer_kb "$fixture/destination" \
  "$fixture/source/does-not-exist" 2>&1 >/dev/null)"
error_status=$?
set -e

if [[ "$error_status" -eq 0 ]]; then
  printf 'FAIL: unreadable/missing source item should fail the space check\n' >&2
  exit 1
fi

if [[ "$error_output" != *"$fixture/source/does-not-exist"* ]]; then
  printf 'FAIL: space-check error should identify the problem path\n' >&2
  exit 1
fi

printf 'Remaining-space test passed.\n'
