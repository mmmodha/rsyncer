# External Disk Transfer for macOS

An interactive Terminal script for safely copying data between mounted disks.

## Features

- Choose source and destination disks from a menu.
- Copy everything or select specific top-level files and folders.
- Check destination free space before copying, with a 5% safety margin.
- Display a live per-file progress bar.
- Verify copied contents using checksums.
- Resume interrupted transfers by merging into existing destination folders.
- Skip unchanged files, add missing files, and update changed files in place.
- Repair checksum mismatches that normal size/time comparison would miss.
- Preserve the source without creating renamed duplicate copies.
- Ignore protected macOS housekeeping folders that the destination regenerates.

## Usage

Download `external-disk-transfer.sh`, then run:

```bash
chmod +x external-disk-transfer.sh
./external-disk-transfer.sh
```

The script uses the `rsync` version included with macOS. Both disks must already
be mounted and visible under `/Volumes`.

## Safety

The script copies data; it does not delete anything from the source. Existing
folders are merged using the same relative paths, so rerunning the script does
not create `copy`, `copy 2`, or similarly renamed duplicates. Files that exist
only at the destination are left untouched.

“Copy everything” excludes `.Spotlight-V100`, `.Trashes`, `.fseventsd`,
`.TemporaryItems`, and other macOS-managed volume metadata. These are not user
data and are recreated automatically by macOS.
