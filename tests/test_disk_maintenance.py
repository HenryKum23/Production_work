# =============================================================
# Script:       test_disk_maintenance.py
# Description:  Unit tests for disk_maintenance.py
# Author:       Henry Kumah
# Created:      2026-03-01
# Version:      1.0
# Usage:        pytest tests/ -v
# Dependencies: pytest (pip install pytest)
# =============================================================

import os
import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta
from scripts.disk_maintenance import (
    get_disk_usage_percent,
    delete_old_logs,
    send_alert,
)


# ── Tests for get_disk_usage_percent() ────────────────────────

def test_disk_usage_returns_a_percentage():
    """Result must be a number between 0 and 100."""
    result = get_disk_usage_percent("/")
    assert 0 <= result <= 100


def test_disk_usage_returns_float():
    """Result must be a float, not a string or None."""
    result = get_disk_usage_percent("/")
    assert isinstance(result, float)


# ── Tests for delete_old_logs() ───────────────────────────────

def test_old_files_are_deleted(tmp_path):
    """Files older than 30 days must be deleted."""
    old_file = tmp_path / "old.log"
    old_file.write_text("old log content")

    # Set the file's modification time to 40 days ago
    old_time = (datetime.now() - timedelta(days=40)).timestamp()
    os.utime(old_file, (old_time, old_time))

    deleted = delete_old_logs(str(tmp_path), days_old=30)

    assert deleted == 1
    assert not old_file.exists()


def test_recent_files_are_not_deleted(tmp_path):
    """Files newer than 30 days must not be touched."""
    recent_file = tmp_path / "recent.log"
    recent_file.write_text("recent log content")

    deleted = delete_old_logs(str(tmp_path), days_old=30)

    assert deleted == 0
    assert recent_file.exists()


def test_only_old_files_deleted_when_mixed(tmp_path):
    """Only old files deleted when both old and recent files exist."""
    old_file = tmp_path / "old.log"
    old_file.write_text("old")
    old_time = (datetime.now() - timedelta(days=40)).timestamp()
    os.utime(old_file, (old_time, old_time))

    recent_file = tmp_path / "recent.log"
    recent_file.write_text("recent")

    deleted = delete_old_logs(str(tmp_path), days_old=30)

    assert deleted == 1
    assert not old_file.exists()
    assert recent_file.exists()


def test_empty_directory_returns_zero(tmp_path):
    """An empty directory should return 0 deleted files."""
    deleted = delete_old_logs(str(tmp_path), days_old=30)
    assert deleted == 0


# ── Tests for send_alert() ────────────────────────────────────

@patch("scripts.disk_maintenance.boto3.client")
def test_send_alert_calls_sns_publish(mock_boto_client):
    """send_alert must call SNS publish with the correct parameters."""
    mock_sns = MagicMock()
    mock_boto_client.return_value = mock_sns

    send_alert("Test alert message")

    mock_boto_client.assert_called_once_with("sns", region_name="eu-west-1")
    mock_sns.publish.assert_called_once()

    call_kwargs = mock_sns.publish.call_args.kwargs
    assert call_kwargs["Message"] == "Test alert message"
    assert call_kwargs["Subject"] == "Disk Alert — Production Server"


@patch("scripts.disk_maintenance.boto3.client")
def test_send_alert_does_not_raise_on_success(mock_boto_client):
    """send_alert must not raise an exception on a successful publish."""
    mock_boto_client.return_value = MagicMock()
    try:
        send_alert("No error expected")
    except Exception as e:
        pytest.fail(f"send_alert raised an unexpected exception: {e}")
