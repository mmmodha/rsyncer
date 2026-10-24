#!/bin/bash

set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/external-disk-transfer.sh"

fixture="$(mktemp -d -t rsyncer-resume.XXXXXX)"
trap 'rm -rf "$fixture"' EXIT

TEST_SOURCE_VOLUME="$fixture/source"
TEST_DESTINATION_VOLUME="$fixture/destination"
mkdir -p "$TEST_SOURCE_VOLUME/Photos" "$TEST_DESTINATION_VOLUME/Photos"

printf 'already identical\n' >"$TEST_SOURCE_VOLUME/Photos/same.txt"
printf 'already identical\n' >"$TEST_DESTINATION_VOLUME/Photos/same.txt"
printf 'new source version with more data\n' >"$TEST_SOURCE_VOLUME/Photos/changed.txt"
printf 'old\n' >"$TEST_DESTINATION_VOLUME/Photos/changed.txt"
printf 'missing from destination\n' >"$TEST_SOURCE_VOLUME/Photos/new.txt"
printf 'AAAA\n' >"$TEST_SOURCE_VOLUME/Photos/same-size-corrupt.txt"
printf 'BBBB\n' >"$TEST_DESTINATION_VOLUME/Photos/same-size-corrupt.txt"
touch -r "$TEST_SOURCE_VOLUME/Photos/same-size-corrupt.txt" \
  "$TEST_DESTINATION_VOLUME/Photos/same-size-corrupt.txt"

choose_volume() {
  if [[ "$1" == *SOURCE* ]]; then
    printf '%s\n' "$TEST_SOURCE_VOLUME"
  else
    printf '%s\n' "$TEST_DESTINATION_VOLUME"
  fi
}

set +e
transfer_output="$(printf '1\ny\n' | main 2>&1)"
transfer_status=$?
set -e

if [[ "$transfer_status" -ne 0 ]]; then
  printf 'FAIL: rerunning against an existing destination should succeed\n' >&2
  printf '%s\n' "$transfer_output" >&2
  exit 1
fi

if ! cmp -s "$TEST_SOURCE_VOLUME/Photos/changed.txt" "$TEST_DESTINATION_VOLUME/Photos/changed.txt"; then
  printf 'FAIL: changed destination file was not updated\n' >&2
  exit 1
fi

if ! cmp -s "$TEST_SOURCE_VOLUME/Photos/new.txt" "$TEST_DESTINATION_VOLUME/Photos/new.txt"; then
  printf 'FAIL: missing destination file was not added\n' >&2
  exit 1
fi

if ! cmp -s "$TEST_SOURCE_VOLUME/Photos/same-size-corrupt.txt" \
  "$TEST_DESTINATION_VOLUME/Photos/same-size-corrupt.txt"; then
  printf 'FAIL: same-size corrupt file was not repaired\n' >&2
  exit 1
fi

duplicate_count="$(find "$TEST_DESTINATION_VOLUME" -name same.txt -type f | wc -l | tr -d ' ')"
if [[ "$duplicate_count" -ne 1 ]]; then
  printf 'FAIL: identical file was duplicated\n' >&2
  exit 1
fi

printf 'Resume/merge test passed.\n'
