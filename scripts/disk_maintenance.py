#!/usr/bin/env python3
# =============================================================
# Script:      disk_maintenance.py
# Description: Cleans old logs and alerts if disk usage is high
# Author:      Henry Kumah
# Created:     2024-01-15
# Version:     1.0
# Usage:       python3 disk_maintenance.py
# =============================================================

# disk_maintenance.py — runs nightly via cron

import os
import shutil
import boto3
from datetime import datetime, timedelta

LOGS_DIR = "/var/log/app"
THRESHOLD_PERCENT = 80
SNS_TOPIC_ARN = "arn:aws:sns:eu-west-1:123456789:ops-alerts"

def get_disk_usage_percent(path="/"):
    total, used, free = shutil.disk_usage(path)
    return (used / total) * 100

def delete_old_logs(directory, days_old=30):
    cutoff = datetime.now() - timedelta(days=days_old)
    deleted = 0
    for filename in os.listdir(directory):
        filepath = os.path.join(directory, filename)
        modified = datetime.fromtimestamp(os.path.getmtime(filepath))
        if modified < cutoff:
            os.remove(filepath)
            deleted += 1
    return deleted

def send_alert(message):
    sns = boto3.client("sns", region_name="eu-west-1")
    sns.publish(TopicArn=SNS_TOPIC_ARN, Message=message, Subject="Disk Alert")

if __name__ == "__main__":
    deleted = delete_old_logs(LOGS_DIR)
    print(f"Deleted {deleted} old log files")

    usage = get_disk_usage_percent()
    print(f"Disk usage: {usage:.1f}%")

    if usage > THRESHOLD_PERCENT:
        send_alert(f"WARNING: Disk usage at {usage:.1f}% on prod server")

#This runs nightly via cron to clean up old log files and alert if disk is getting full

# Cron job — runs disk_maintenance.py every night at 2am
0 2 * * * /usr/bin/python3 /opt/scripts/disk_maintenance.py

# Or via a CI/CD pipeline step in GitHub Actions
# - name: Bootstrap new server
#   run: bash scripts/bootstrap.sh
#   env:
#     AWS_REGION: eu-west-1
