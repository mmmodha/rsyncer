#!/bin/bash

# Interactive, verified transfer between mounted macOS volumes.
# The source is never deleted. Existing destination folders are merged safely.

set -u

parse_selection() {
  local input="$1"
  local count="$2"
  local token
  local chosen=" "
  local normalized
  local -a tokens=()

  normalized="${input//,/ }"
  if [[ "$normalized" == "all" || "$normalized" == "ALL" ]]; then
    token=1
    while [[ "$token" -le "$count" ]]; do
      printf '%s\n' "$((token - 1))"
      token=$((token + 1))
    done
    return 0
  fi

  [[ -n "${normalized//[[:space:]]/}" ]] || return 1

  tokens=($normalized)
  for token in "${tokens[@]}"; do
    [[ "$token" =~ ^[0-9]+$ ]] || return 1
    [[ "$token" -ge 1 && "$token" -le "$count" ]] || return 1
  done

  for token in "${tokens[@]}"; do
    if [[ "$chosen" != *" $token "* ]]; then
      printf '%s\n' "$((token - 1))"
      chosen="${chosen}${token} "
    fi
  done
}

selected_item_path() {
  printf '%s/%s\n' "${1%/}" "$2"
}

destination_is_safe() {
  [[ "${1%/}" != "${2%/}" ]]
}

space_is_sufficient() {
  [[ "$1" -le "$2" ]]
}

format_kb() {
  awk -v kb="$1" 'BEGIN {
    if (kb >= 1073741824) printf "%.1f TiB\n", kb / 1073741824;
    else if (kb >= 1048576) printf "%.1f GiB\n", kb / 1048576;
    else if (kb >= 1024) printf "%.1f MiB\n", kb / 1024;
    else printf "%d KiB\n", kb;
  }'
}

required_space_kb() {
  local item
  local result
  local item_kb
  local total=0

  for item in "$@"; do
    result="$(du -sk "$item" 2>/dev/null)" || return 1
    item_kb="${result%%[[:space:]]*}"
    [[ "$item_kb" =~ ^[0-9]+$ ]] || return 1
    total=$((total + item_kb))
  done
  printf '%s\n' "$total"
}

remaining_transfer_kb() {
  local destination="$1"
  local item
  local stats
  local item_bytes
  local total_bytes=0
  shift

  for item in "$@"; do
    stats="$(LC_ALL=C rsync -aEHn --stats -- "$item" "$destination/" 2>/dev/null)" || return 1
    item_bytes="$(printf '%s\n' "$stats" | awk -F': ' \
      '/^Total transferred file size:/ {print $2; exit}' | awk '{print $1}')"
    item_bytes="${item_bytes//,/}"
    [[ "$item_bytes" =~ ^[0-9]+$ ]] || return 1
    total_bytes=$((total_bytes + item_bytes))
  done

  printf '%s\n' "$(((total_bytes + 1023) / 1024))"
}

available_space_kb() {
  local available
  available="$(df -Pk "$1" 2>/dev/null | awk 'END {print $4}')" || return 1
  [[ "$available" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$available"
}

render_progress_bar() {
  local percent="$1"
  local width="${2:-30}"
  local filled
  local i

  [[ "$percent" -lt 0 ]] && percent=0
  [[ "$percent" -gt 100 ]] && percent=100
  filled=$(((percent * width + 50) / 100))

  printf '['
  i=0
  while [[ "$i" -lt "$width" ]]; do
    if [[ "$i" -lt "$filled" ]]; then
      printf '='
    else
      printf '-'
    fi
    i=$((i + 1))
  done
  printf '] %3d%%' "$percent"
}

copy_with_progress() {
  local source_item="$1"
  local destination="$2"
  local comparison_mode="${3:-quick}"
  local rsync_status
  local line
  local percent
  local -a rsync_options=(-a -E -H --progress)

  if [[ "$comparison_mode" == "checksum" ]]; then
    rsync_options+=(-c)
  fi

  rsync "${rsync_options[@]}" -- "$source_item" "$destination/" 2>&1 |
    tr '\r' '\n' |
    while IFS= read -r line; do
      if [[ "$line" =~ ([0-9]{1,3})% ]]; then
        percent="${BASH_REMATCH[1]}"
        printf '\r'
        render_progress_bar "$percent" 30
        if [[ "$percent" -eq 100 ]]; then
          printf '\n'
        fi
      elif [[ -n "${line//[[:space:]]/}" ]]; then
        printf '  %s\n' "$line"
      fi
    done
  rsync_status="${PIPESTATUS[0]}"
  return "$rsync_status"
}

choose_volume() {
  local prompt="$1"
  local excluded="${2:-}"
  local volume
  local choice
  local i
  local -a volumes=()

  shopt -s nullglob
  for volume in /Volumes/*; do
    [[ -d "$volume" ]] || continue
    [[ -n "$excluded" && "${volume%/}" == "${excluded%/}" ]] && continue
    volumes+=("$volume")
  done
  shopt -u nullglob

  if [[ "${#volumes[@]}" -eq 0 ]]; then
    printf 'No eligible mounted volumes were found in /Volumes.\n' >&2
    return 1
  fi

  while true; do
    printf '\n%s\n' "$prompt" >&2
    i=0
    while [[ "$i" -lt "${#volumes[@]}" ]]; do
      printf '  %d) %s\n' "$((i + 1))" "${volumes[$i]}" >&2
      i=$((i + 1))
    done
    printf 'Enter a number: ' >&2
    IFS= read -r choice || return 1
    if [[ "$choice" =~ ^[0-9]+$ ]] && \
       [[ "$choice" -ge 1 && "$choice" -le "${#volumes[@]}" ]]; then
      printf '%s\n' "${volumes[$((choice - 1))]}"
      return 0
    fi
    printf 'Please enter one of the listed numbers.\n' >&2
  done
}

verify_item() {
  local source_item="$1"
  local destination="$2"
  local report_file="$3"

  : >"$report_file"
  if ! rsync -rlnci -- "$source_item" "$destination/" >"$report_file" 2>&1; then
    return 1
  fi
  [[ ! -s "$report_file" ]]
}

main() {
  local source_volume
  local destination_volume
  local answer
  local copy_mode
  local selection
  local index
  local item
  local verify_report
  local required_kb
  local available_kb
  local required_with_headroom_kb
  local copied=0
  local failed=0
  local i
  local -a items=()
  local -a selected_indexes=()
  local -a selected_items=()

  if ! command -v rsync >/dev/null 2>&1; then
    printf 'Error: rsync is required but was not found.\n' >&2
    return 1
  fi

  printf 'External Disk Transfer\n'
  printf 'Copies selected items and verifies them by checksum.\n'
  printf 'The source is not deleted; existing folders are resumed and merged.\n'

  source_volume="$(choose_volume 'Choose the SOURCE disk:')" || return 1
  destination_volume="$(choose_volume 'Choose the DESTINATION disk:' "$source_volume")" || return 1

  if ! destination_is_safe "$source_volume" "$destination_volume"; then
    printf 'Error: source and destination must be different volumes.\n' >&2
    return 1
  fi
  if [[ ! -w "$destination_volume" ]]; then
    printf 'Error: destination is not writable: %s\n' "$destination_volume" >&2
    return 1
  fi

  shopt -s nullglob dotglob
  items=("$source_volume"/*)
  shopt -u nullglob dotglob

  if [[ "${#items[@]}" -eq 0 ]]; then
    printf 'The source disk contains no items to copy.\n' >&2
    return 1
  fi

  while true; do
    printf '\nCopy mode:\n'
    printf '  1) Copy everything from the source disk\n'
    printf '  2) Choose specific files and folders\n'
    printf 'Enter a number: '
    IFS= read -r copy_mode || return 1
    [[ "$copy_mode" == "1" || "$copy_mode" == "2" ]] && break
    printf 'Please enter 1 or 2.\n' >&2
  done

  if [[ "$copy_mode" == "1" ]]; then
    while IFS= read -r index; do
      selected_indexes+=("$index")
    done < <(parse_selection all "${#items[@]}")
  else
    printf '\nItems on %s:\n' "$source_volume"
    i=0
    while [[ "$i" -lt "${#items[@]}" ]]; do
      printf '  %d) %s\n' "$((i + 1))" "${items[$i]##*/}"
      i=$((i + 1))
    done

    while true; do
      printf '\nChoose items (example: 1,3,5) or type all: '
      IFS= read -r selection || return 1
      selected_indexes=()
      while IFS= read -r index; do
        [[ -n "$index" ]] && selected_indexes+=("$index")
      done < <(parse_selection "$selection" "${#items[@]}")
      if [[ "${#selected_indexes[@]}" -gt 0 ]]; then
        break
      fi
      printf 'Invalid selection. Use listed numbers separated by commas/spaces, or all.\n' >&2
    done
  fi

  for index in "${selected_indexes[@]}"; do
    selected_items+=("${items[$index]}")
  done

  printf '\nChecking required and available disk space...\n'
  required_kb="$(remaining_transfer_kb "$destination_volume" "${selected_items[@]}")" || {
    printf 'Error: could not calculate the data remaining to transfer.\n' >&2
    return 1
  }
  available_kb="$(available_space_kb "$destination_volume")" || {
    printf 'Error: could not read free space on the destination.\n' >&2
    return 1
  }
  required_with_headroom_kb=$(((required_kb * 105 + 99) / 100))

  printf 'Data still to copy:   %s\n' "$(format_kb "$required_kb")"
  printf 'Required with buffer: %s (includes 5%% safety margin)\n' \
    "$(format_kb "$required_with_headroom_kb")"
  printf 'Destination free:     %s\n' "$(format_kb "$available_kb")"

  if ! space_is_sufficient "$required_with_headroom_kb" "$available_kb"; then
    printf 'STOPPED: the destination does not have enough free space. Nothing was copied.\n' >&2
    return 1
  fi

  printf '\nReady to copy %d item(s):\n' "${#selected_indexes[@]}"
  for index in "${selected_indexes[@]}"; do
    printf '  - %s\n' "${items[$index]##*/}"
  done
  printf 'From: %s\nTo:   %s\n' "$source_volume" "$destination_volume"
  printf 'Continue? [y/N] '
  IFS= read -r answer || return 1
  [[ "$answer" == "y" || "$answer" == "Y" ]] || {
    printf 'Cancelled. Nothing was copied.\n'
    return 0
  }

  verify_report="$(mktemp -t external-disk-transfer.XXXXXX)" || return 1
  trap 'rm -f "$verify_report"' EXIT HUP INT TERM

  for index in "${selected_indexes[@]}"; do
    item="${items[$index]}"
    printf '\nCopying: %s\n' "${item##*/}"

    if ! copy_with_progress "$item" "$destination_volume"; then
      printf 'FAILED during copy: %s\n' "${item##*/}" >&2
      failed=$((failed + 1))
      continue
    fi

    printf 'Verifying checksums: %s\n' "${item##*/}"
    if verify_item "$item" "$destination_volume" "$verify_report"; then
      printf 'VERIFIED: %s\n' "${item##*/}"
      copied=$((copied + 1))
    else
      printf 'Mismatch detected; repairing by checksum: %s\n' "${item##*/}" >&2
      if [[ -s "$verify_report" ]]; then
        printf 'rsync comparison details:\n' >&2
        sed 's/^/  /' "$verify_report" >&2
      fi
      if copy_with_progress "$item" "$destination_volume" checksum && \
         verify_item "$item" "$destination_volume" "$verify_report"; then
        printf 'REPAIRED AND VERIFIED: %s\n' "${item##*/}"
        copied=$((copied + 1))
      else
        printf 'VERIFICATION FAILED AFTER REPAIR: %s\n' "${item##*/}" >&2
        failed=$((failed + 1))
      fi
    fi
  done

  rm -f "$verify_report"
  trap - EXIT HUP INT TERM

  printf '\nTransfer summary: %d verified, %d failed.\n' "$copied" "$failed"
  printf 'The source disk was not changed.\n'
  [[ "$failed" -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
