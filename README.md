# External Disk Transfer for macOS

An interactive Terminal script for safely copying data between mounted disks.

## Features

- Choose source and destination disks from a menu.
- Copy everything or select specific top-level files and folders.
- Check destination free space before copying, with a 5% safety margin.
- Display a live per-file progress bar.
- Verify copied contents using checksums.
- Preserve the source and refuse to overwrite existing destination items.

## Usage

Download `external-disk-transfer.sh`, then run:

```bash
chmod +x external-disk-transfer.sh
./external-disk-transfer.sh
```

The script uses the `rsync` version included with macOS. Both disks must already
be mounted and visible under `/Volumes`.

## Safety

The script copies data; it does not delete anything from the source. If an item
with the same name already exists at the destination, that item is skipped.
