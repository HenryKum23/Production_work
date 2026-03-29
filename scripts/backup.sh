#!/bin/bash
# =============================================================
# Script:       backup.sh
# Description:  Backs up application data and logs to an AWS
#               S3 bucket nightly. Creates a timestamped
#               compressed archive of /var/log/app and
#               /etc/nginx, uploads to S3, then removes the
#               local archive to free disk space.
#               Registered as a cron job by bootstrap.sh —
#               runs every night at 1am automatically.
# Author:       Henry Kumah
# Created:      2026-03-01
# Version:      1.0
# Usage:        Automatic via cron (see bootstrap.sh)
#               Manual run: sudo bash scripts/backup.sh
# Dependencies: AWS CLI configured with s3:PutObject permission,
#               tar (pre-installed on Ubuntu)
# =============================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────
S3_BUCKET="hfm-app-backups"
AWS_REGION="eu-west-1"
BACKUP_DIRS="/var/log/app /etc/nginx"
BACKUP_STAGING="/tmp/backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVE_NAME="backup_${TIMESTAMP}.tar.gz"
SCRIPT_LOG="/var/log/backup.log"

exec >> "$SCRIPT_LOG" 2>&1

echo "=== Backup started: $(date) ==="

# ── Step 1: Create staging directory ──────────────────────────
echo "[1/4] Creating staging directory..."
mkdir -p "$BACKUP_STAGING"
echo "      Staging directory ready: $BACKUP_STAGING"

# ── Step 2: Create compressed archive ─────────────────────────
echo "[2/4] Creating compressed archive..."
echo "      Backing up: $BACKUP_DIRS"

# shellcheck disable=SC2086
# Word splitting is intentional here — BACKUP_DIRS is a space
# separated list of paths, not a single path
tar -czf "$BACKUP_STAGING/$ARCHIVE_NAME" $BACKUP_DIRS

ARCHIVE_SIZE=$(du -sh "$BACKUP_STAGING/$ARCHIVE_NAME" | cut -f1)
echo "      Archive created: $ARCHIVE_NAME ($ARCHIVE_SIZE)"

# ── Step 3: Upload archive to S3 ──────────────────────────────
echo "[3/4] Uploading to S3..."

aws s3 cp "$BACKUP_STAGING/$ARCHIVE_NAME" \
  "s3://$S3_BUCKET/backups/$ARCHIVE_NAME" \
  --region "$AWS_REGION"

echo "      Uploaded to: s3://$S3_BUCKET/backups/$ARCHIVE_NAME"

# Verify the upload succeeded by checking the object exists
aws s3 ls "s3://$S3_BUCKET/backups/$ARCHIVE_NAME" \
  --region "$AWS_REGION" > /dev/null

echo "      Upload verified successfully."

# ── Step 4: Clean up local staging archive ────────────────────
echo "[4/4] Cleaning up local staging archive..."
rm -f "$BACKUP_STAGING/$ARCHIVE_NAME"
echo "      Local archive removed. Disk space freed."

echo "=== Backup complete: $(date) ==="
echo "=== Backup stored at: s3://$S3_BUCKET/backups/$ARCHIVE_NAME ==="