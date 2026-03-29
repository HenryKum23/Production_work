#!/bin/bash
# =============================================================
# Script:       log_rotation.sh
# Description:  Rotates application and system logs on a weekly
#               schedule. Compresses logs older than 7 days,
#               archives them to /var/log/archive, and deletes
#               archives older than 90 days to free disk space.
#               Registered as a cron job by bootstrap.sh —
#               runs every Sunday at 3am automatically.
# Author:       Henry Kumah
# Created:      2026-03-01
# Version:      1.0
# Usage:        Automatic via cron (see bootstrap.sh)
#               Manual run: sudo bash scripts/log_rotation.sh
# Dependencies: gzip (pre-installed on Ubuntu)
# =============================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────
LOG_DIR="/var/log/app"
ARCHIVE_DIR="/var/log/archive"
COMPRESS_AFTER_DAYS=7        # compress logs older than 7 days
DELETE_AFTER_DAYS=90         # delete archives older than 90 days
SCRIPT_LOG="/var/log/log_rotation.log"

exec >> "$SCRIPT_LOG" 2>&1

echo "=== Log rotation started: $(date) ==="

# ── Step 1: Create archive directory if it doesn't exist ──────
echo "[1/4] Checking archive directory..."
mkdir -p "$ARCHIVE_DIR"
echo "      Archive directory ready: $ARCHIVE_DIR"

# ── Step 2: Compress logs older than 7 days ───────────────────
echo "[2/4] Compressing logs older than $COMPRESS_AFTER_DAYS days..."
COMPRESSED=0

find "$LOG_DIR" -type f -name "*.log" -mtime +"$COMPRESS_AFTER_DAYS" | \
while read -r filepath; do
  filename=$(basename "$filepath")

  # Skip files already compressed
  if [[ "$filename" == *.gz ]]; then
    continue
  fi

  gzip -c "$filepath" > "$ARCHIVE_DIR/${filename}.gz"
  rm -f "$filepath"
  COMPRESSED=$((COMPRESSED + 1))
  echo "      Compressed: $filename"
done

echo "      Compression complete."

# ── Step 3: Delete archives older than 90 days ────────────────
echo "[3/4] Deleting archives older than $DELETE_AFTER_DAYS days..."
DELETED=0

find "$ARCHIVE_DIR" -type f -name "*.gz" -mtime +"$DELETE_AFTER_DAYS" | \
while read -r filepath; do
  filename=$(basename "$filepath")
  rm -f "$filepath"
  DELETED=$((DELETED + 1))
  echo "      Deleted archive: $filename"
done

echo "      Archive cleanup complete."

# ── Step 4: Report current disk usage after rotation ──────────
echo "[4/4] Disk usage after rotation..."
df -h /var/log | tail -1 | awk '{print "      /var/log usage: " $3 " used of " $2 " (" $5 " full)"}'

echo "=== Log rotation complete: $(date) ==="