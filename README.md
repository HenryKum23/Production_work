# AWS Production Automation — Server Bootstrap, Maintenance & CI/CD Pipeline

> **Author:** Henry Kumah  
> **Purpose:** Demonstrates production-grade automation using Bash, Python, and GitHub Actions on AWS  
> **Stack:** AWS (EC2, SNS, Secrets Manager, ECR, ECS), GitHub Actions, Docker, Nginx  
> **Last Updated:** March 2026

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Repository Structure](#4-repository-structure)
5. [AWS Setup](#5-aws-setup)
6. [Script 1 — Server Bootstrap (Bash)](#6-script-1--server-bootstrap-bash)
7. [Script 2 — Disk Maintenance (Python)](#7-script-2--disk-maintenance-python)
8. [CI/CD Pipeline — GitHub Actions](#8-cicd-pipeline--github-actions)
9. [GitHub Secrets Configuration](#9-github-secrets-configuration)
10. [Running Locally for Testing](#10-running-locally-for-testing)
11. [Deployment Walkthrough](#11-deployment-walkthrough)
12. [Monitoring & Alerting](#12-monitoring--alerting)
13. [Troubleshooting](#13-troubleshooting)
14. [Security Considerations](#14-security-considerations)

---

## 1. Project Overview

This project demonstrates three core DevOps automation skills applied to a real AWS production environment:

| Script / File | Purpose |
|---|---|
| `scripts/bootstrap.sh` | Provisions and configures a fresh Ubuntu EC2 server in one run |
| `scripts/disk_maintenance.py` | Nightly maintenance — cleans old logs, alerts ops team if disk is high |
| `.github/workflows/deploy.yml` | Full CI/CD pipeline — test, build, deploy, notify |

The goal is to eliminate manual server configuration, reduce human error, and ensure every server in the fleet is identical and reproducible — a critical requirement in high-availability environments like financial services infrastructure.

---

## 2. Architecture

```
Developer pushes to main branch
           │
           ▼
  GitHub Actions Pipeline
  ┌─────────────────────────────────────┐
  │  Stage 1: Test & Validate           │
  │  - Lint Python (flake8)             │
  │  - Lint Bash (shellcheck)           │
  │  - Run unit tests (pytest)          │
  └──────────────┬──────────────────────┘
                 │ pass
                 ▼
  ┌─────────────────────────────────────┐
  │  Stage 2: Build                     │
  │  - Build Docker image               │
  │  - Push to Amazon ECR               │
  └──────────────┬──────────────────────┘
                 │ pass
                 ▼
  ┌─────────────────────────────────────┐
  │  Stage 3: Deploy                    │
  │  - Run bootstrap.sh on new servers  │
  │  - Run disk_maintenance.py          │
  │  - Deploy new image to ECS          │
  │  - Wait for stable health           │
  │  - Notify team via SNS              │
  └─────────────────────────────────────┘

AWS Infrastructure
  ┌──────────────────────────────────────────┐
  │  VPC                                     │
  │  ┌─────────────┐   ┌──────────────────┐  │
  │  │ Public      │   │ Private Subnet   │  │
  │  │ Subnet      │   │                  │  │
  │  │  ALB        │──▶│  EC2 / ECS       │  │
  │  └─────────────┘   └──────────────────┘  │
  │                                          │
  │  ECR ── Secrets Manager ── SNS           │
  └──────────────────────────────────────────┘
```

---

## 3. Prerequisites

### Local machine

- AWS CLI v2 installed and configured (`aws configure`)
- Python 3.11+
- Docker Desktop
- Git
- `shellcheck` — for Bash linting (`apt install shellcheck` or `brew install shellcheck`)

### AWS account requirements

- IAM user or role with the following permissions:
  - `ec2:*`
  - `secretsmanager:GetSecretValue`
  - `sns:Publish`
  - `ecr:*`
  - `ecs:*`
- An existing VPC with at least one public and one private subnet
- An EC2 key pair for SSH access

### Verify AWS CLI is configured

```bash
aws sts get-caller-identity
```

Expected output:

```json
{
    "UserId": "AIDAEXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/henry"
}
```

---

## 4. Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD pipeline definition
├── scripts/
│   ├── aws_setup.sh            # One-command AWS resource provisioning
│   ├── bootstrap.sh            # Server configuration script
│   └── disk_maintenance.py     # Nightly disk cleanup and alerting
├── tests/
│   └── test_disk_maintenance.py  # Unit tests for Python script
├── app/
│   └── Dockerfile              # Application container definition
├── requirements.txt            # Python dependencies
└── README.md                   # This file
```

---

## 5. AWS Setup

Rather than running individual CLI commands for each resource, all four AWS setup steps are handled by a single script — `scripts/aws_setup.sh`. This is the correct production approach: repeatable, version-controlled, and executable in one command.

> **Why a script and not raw CLI commands?**
> Running individual CLI commands manually is error-prone — you might miss a step, use a wrong value, or be unable to reproduce the setup later. A script captures every step in order, validates each one succeeded before continuing, logs the output, and can be re-run safely on a fresh environment.

> **On the Secrets Manager step:** This project contains no real application credentials. A demo placeholder value is stored in Secrets Manager solely to demonstrate the production pattern of fetching secrets at runtime rather than hardcoding them in scripts. The full explanation lives in the script header comments. In a real deployment you would replace the placeholder with an actual credential — an API key, a service token, a password — whatever your application needs. The fetch mechanism in `bootstrap.sh` remains identical regardless of what the secret contains.

---

### The setup script

**File:** `scripts/aws_setup.sh`

```bash
#!/bin/bash
# =============================================================
# Script:       aws_setup.sh
# Description:  Provisions all required AWS resources for this
#               project in one run — SNS, Secrets Manager,
#               ECR, and EC2
# Author:       Henry Kumah
# Created:      2026-03-01
# Version:      1.0
# Usage:        bash scripts/aws_setup.sh
# Dependencies: AWS CLI v2 configured with appropriate IAM
#               permissions, jq installed (apt install jq)
# =============================================================

set -euo pipefail

# ── Configuration — edit these before running ─────────────────
AWS_REGION="eu-west-1"
ALERT_EMAIL="your@email.com"
ECR_REPO_NAME="hfm-app"
INSTANCE_TYPE="t3.micro"
AMI_ID="ami-0694d931cee176e7d"       # Ubuntu 22.04 LTS eu-west-1
KEY_PAIR_NAME="your-key-pair-name"
SUBNET_ID="subnet-xxxxxxxxxx"
SECURITY_GROUP_ID="sg-xxxxxxxxxx"
SERVER_NAME="prod-server-01"

# ── Secrets Manager placeholder ───────────────────────────────
# This project contains no real application credentials.
# A demo placeholder is stored here solely to demonstrate the
# production pattern of fetching secrets from AWS Secrets Manager
# at runtime rather than hardcoding them in scripts.
#
# In a real deployment you would replace this value with an actual
# credential — for example an API key, a service password, or an
# access token — depending on what your application needs.
# The fetch pattern in bootstrap.sh remains identical regardless
# of what the secret contains.

SECRET_NAME="prod/app/secret"
SECRET_VALUE="demo-placeholder-value"

LOG="aws_setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== AWS setup started: $(date) ==="

# ── Step 1: Create SNS topic ───────────────────────────────────
echo ""
echo "[1/4] Creating SNS topic for ops alerts..."

SNS_TOPIC_ARN=$(aws sns create-topic \
  --name ops-alerts \
  --region "$AWS_REGION" \
  --query TopicArn \
  --output text)

echo "      SNS topic created: $SNS_TOPIC_ARN"

aws sns subscribe \
  --topic-arn "$SNS_TOPIC_ARN" \
  --protocol email \
  --notification-endpoint "$ALERT_EMAIL" \
  --region "$AWS_REGION" > /dev/null

echo "      Subscription request sent to: $ALERT_EMAIL"
echo "      ACTION REQUIRED: Check your inbox and confirm the subscription."

# ── Step 2: Store demo placeholder in Secrets Manager ─────────
echo ""
echo "[2/4] Storing demo placeholder in AWS Secrets Manager..."
echo "      (See script header comments for full context)"

aws secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --secret-string "$SECRET_VALUE" \
  --region "$AWS_REGION" > /dev/null

echo "      Secret stored at path: $SECRET_NAME"

# Verify the secret was stored correctly before continuing
STORED=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --query SecretString \
  --output text \
  --region "$AWS_REGION")

if [[ "$STORED" == "$SECRET_VALUE" ]]; then
  echo "      Secret verified successfully."
else
  echo "      ERROR: Secret verification failed. Exiting."
  exit 1
fi

# ── Step 3: Create ECR repository ─────────────────────────────
echo ""
echo "[3/4] Creating ECR repository..."

ECR_URI=$(aws ecr create-repository \
  --repository-name "$ECR_REPO_NAME" \
  --region "$AWS_REGION" \
  --query repository.repositoryUri \
  --output text)

echo "      ECR repository created: $ECR_URI"

# ── Step 4: Launch EC2 instance ───────────────────────────────
echo ""
echo "[4/4] Launching EC2 instance..."

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_PAIR_NAME" \
  --security-group-ids "$SECURITY_GROUP_ID" \
  --subnet-id "$SUBNET_ID" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$SERVER_NAME}]" \
  --region "$AWS_REGION" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "      Instance launched: $INSTANCE_ID"
echo "      Waiting for instance to reach running state..."

aws ec2 wait instance-running \
  --instance-ids "$INSTANCE_ID" \
  --region "$AWS_REGION"

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text \
  --region "$AWS_REGION")

echo "      Instance is running."
echo "      Public IP: $PUBLIC_IP"

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "============================================================"
echo " AWS setup complete: $(date)"
echo "============================================================"
echo " SNS Topic ARN  : $SNS_TOPIC_ARN"
echo " Secret path    : $SECRET_NAME"
echo " ECR URI        : $ECR_URI"
echo " Instance ID    : $INSTANCE_ID"
echo " Public IP      : $PUBLIC_IP"
echo "============================================================"
echo " Next steps:"
echo "   1. Confirm the SNS email subscription in your inbox"
echo "   2. Add SNS_TOPIC_ARN to GitHub Secrets (see README Section 9)"
echo "   3. Run bootstrap.sh on the EC2 instance:"
echo "      scp scripts/bootstrap.sh ubuntu@$PUBLIC_IP:/home/ubuntu/"
echo "      ssh ubuntu@$PUBLIC_IP 'sudo bash bootstrap.sh'"
echo "============================================================"
echo ""
echo " Full log saved to: $LOG"
```
This file is exactly the same as aws_setup.sh under the /production/scripts/aws_setup.sh
---

### How to run it

**Step 1** — Edit the configuration block at the top of the script with your actual values:

```bash
ALERT_EMAIL="your@email.com"
KEY_PAIR_NAME="your-key-pair-name"
SUBNET_ID="subnet-xxxxxxxxxx"
SECURITY_GROUP_ID="sg-xxxxxxxxxx"
```

**Step 2** — Run it:

```bash
bash scripts/aws_setup.sh
```

**Step 3** — The script prints a summary of everything created at the end:

```
============================================================
 AWS setup complete: Sun Mar 29 14:32:11 UTC 2026
============================================================
 SNS Topic ARN  : arn:aws:sns:eu-west-1:123456789012:ops-alerts
 Secret path    : prod/app/secret
 ECR URI        : 123456789012.dkr.ecr.eu-west-1.amazonaws.com/hfm-app
 Instance ID    : i-0abc123def456789
 Public IP      : 54.72.xxx.xxx
============================================================
 Next step: Add SNS_TOPIC_ARN to GitHub Secrets
 Then run:  bash scripts/bootstrap.sh on the EC2 instance
============================================================
```

Copy the SNS Topic ARN from this output — you will need it in the GitHub Secrets configuration step.

**Step 4** — Check your email and confirm the SNS subscription.

---

## 6. Script 1 — Server Bootstrap (Bash)

**File:** `scripts/bootstrap.sh`

This script is designed to run once on a fresh EC2 instance. It takes a bare Ubuntu server and transforms it into a fully configured, secured, production-ready application server in a single execution.

### What it does

1. Locks down Bash to fail fast on any error (`set -euo pipefail`)
2. Logs all output to `/var/log/bootstrap.log`
3. Updates the OS and installs required packages
4. Creates a non-privileged application user
5. Fetches a demo placeholder from AWS Secrets Manager — demonstrating the runtime secret fetch pattern (no real credential exists in this project)
6. Writes and enables the Nginx configuration
7. Configures the UFW firewall — allows only ports 22, 80, 443

### The script

```bash
#!/bin/bash
# =============================================================
# Script:       bootstrap.sh
# Description:  Provisions and configures a fresh Ubuntu EC2 server
# Author:       Henry Kumah
# Created:      2026-03-01
# Version:      1.0
# Usage:        sudo bash bootstrap.sh
# Dependencies: AWS CLI configured with appropriate IAM permissions
# =============================================================

set -euo pipefail

LOG="/var/log/bootstrap.log"
exec >> "$LOG" 2>&1

echo "=== Bootstrap started: $(date) ==="

# ── 1. Update OS ──────────────────────────────────────────────
echo "[1/6] Updating OS packages..."
apt-get update -y && apt-get upgrade -y

# ── 2. Install packages ───────────────────────────────────────
echo "[2/6] Installing required packages..."
apt-get install -y nginx postgresql-client awscli curl unzip

# ── 3. Create application user ────────────────────────────────
echo "[3/6] Creating application user..."
useradd --system --no-create-home --shell /usr/sbin/nologin appuser

# ── 4. Fetch demo secret from AWS Secrets Manager ────────────
# This project contains no real application credentials.
# This step demonstrates the production pattern of fetching a
# secret at runtime. In a real deployment, replace SECRET_NAME
# with your actual secret path and use the fetched value where
# your application needs it (e.g. passed as an env variable to
# a service). The fetch mechanism is identical regardless of
# what the secret contains.
echo "[4/6] Fetching secret from AWS Secrets Manager..."
APP_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id prod/app/secret \
  --query SecretString \
  --output text \
  --region eu-west-1)
echo "      Secret fetched successfully."

# ── 5. Configure Nginx ────────────────────────────────────────
echo "[5/6] Configuring Nginx..."
cat > /etc/nginx/sites-available/app.conf << EOF
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:8080;
    }
}
EOF

ln -sf /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/
nginx -t && systemctl enable nginx && systemctl restart nginx

# ── 6. Configure firewall ─────────────────────────────────────
echo "[6/6] Configuring firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "=== Bootstrap complete: $(date) ==="
```

### How to run it on your EC2 instance

Copy the script to the server and execute it:

```bash
# Copy script to server
scp -i ~/.ssh/your-key.pem scripts/bootstrap.sh ubuntu@<EC2-PUBLIC-IP>:/home/ubuntu/

# SSH into the server
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2-PUBLIC-IP>

# Run the bootstrap script
sudo bash bootstrap.sh
```

### Verify it worked

```bash
# Check the log
sudo cat /var/log/bootstrap.log

# Verify Nginx is running
systemctl status nginx

# Verify firewall is active
sudo ufw status

# Verify the app user was created
id appuser
```

---

## 7. Script 2 — Disk Maintenance (Python)

**File:** `scripts/disk_maintenance.py`

This script runs nightly via cron. It cleans up log files older than 30 days, then checks disk usage. If disk is still above 80% after cleanup, it fires an alert to the ops team via AWS SNS.

### What it does

1. Deletes all files in `/var/log/app` older than 30 days
2. Calculates current disk usage percentage
3. If usage exceeds 80%, publishes an alert to the SNS topic

### The script

```python
#!/usr/bin/env python3
# =============================================================
# Script:       disk_maintenance.py
# Description:  Cleans old log files and alerts if disk usage is high
# Author:       Henry Kumah
# Created:      2026-03-01
# Version:      1.0
# Usage:        python3 disk_maintenance.py
# Dependencies: boto3, AWS credentials configured
# =============================================================

import os
import shutil
import boto3
from datetime import datetime, timedelta

# ── Constants ─────────────────────────────────────────────────
LOGS_DIR = "/var/log/app"
THRESHOLD_PERCENT = 80
SNS_TOPIC_ARN = "arn:aws:sns:eu-west-1:123456789012:ops-alerts"


def get_disk_usage_percent(path="/"):
    """Returns current disk usage as a percentage for the given path."""
    total, used, free = shutil.disk_usage(path)
    return (used / total) * 100


def delete_old_logs(directory, days_old=30):
    """Deletes files older than days_old from directory. Returns count deleted."""
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
    """Publishes a message to the ops SNS topic."""
    sns = boto3.client("sns", region_name="eu-west-1")
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Message=message,
        Subject="Disk Alert — Production Server"
    )


if __name__ == "__main__":
    print(f"=== Disk maintenance started: {datetime.now()} ===")

    # Step 1 — clean old logs
    deleted = delete_old_logs(LOGS_DIR)
    print(f"Deleted {deleted} old log files from {LOGS_DIR}")

    # Step 2 — check disk usage after cleanup
    usage = get_disk_usage_percent()
    print(f"Disk usage after cleanup: {usage:.1f}%")

    # Step 3 — alert if still above threshold
    if usage > THRESHOLD_PERCENT:
        message = f"WARNING: Disk usage at {usage:.1f}% on prod server after log cleanup."
        send_alert(message)
        print(f"Alert sent to ops team via SNS.")
    else:
        print(f"Disk usage is healthy. No alert needed.")

    print(f"=== Disk maintenance complete: {datetime.now()} ===")
```

### Install dependencies

```bash
pip install -r requirements.txt
```

`requirements.txt`:
```
boto3==1.34.0
```

### Schedule it with cron (runs every night at 2am)

```bash
# Open cron editor
crontab -e

# Add this line
0 2 * * * /usr/bin/python3 /opt/scripts/disk_maintenance.py >> /var/log/disk_maintenance.log 2>&1
```

### Run it manually to test

```bash
python3 scripts/disk_maintenance.py
```

---

## 8. CI/CD Pipeline — GitHub Actions

**File:** `.github/workflows/deploy.yml`

The pipeline has three sequential stages. Each stage only runs if the previous one passed.

```
Test & Validate → Build & Push → Deploy to Production
```

### The full pipeline

```yaml
# =============================================================
# Workflow:     deploy.yml
# Description:  CI/CD pipeline — test, build, deploy to AWS
# Author:       Henry Kumah
# Triggers:     Push to main branch
# =============================================================

name: Deploy to Production

on:
  push:
    branches:
      - main

env:
  AWS_REGION: eu-west-1
  PYTHON_VERSION: "3.11"

jobs:

  # ── Stage 1: Test & Validate ─────────────────────────────────
  test:
    name: Test & Validate
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pytest flake8

      - name: Lint Python scripts
        run: flake8 scripts/

      - name: Validate Bash scripts
        run: |
          sudo apt-get install -y shellcheck
          shellcheck scripts/bootstrap.sh

      - name: Run unit tests
        run: pytest tests/ -v

  # ── Stage 2: Build & Push ────────────────────────────────────
  build:
    name: Build & Push Docker Image
    runs-on: ubuntu-latest
    needs: test

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Log in to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push Docker image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/hfm-app:$IMAGE_TAG .
          docker push $ECR_REGISTRY/hfm-app:$IMAGE_TAG

  # ── Stage 3: Deploy ──────────────────────────────────────────
  deploy:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: build
    environment: production

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Install Python dependencies
        run: pip install -r requirements.txt

      - name: Run disk maintenance
        run: python3 scripts/disk_maintenance.py

      - name: Deploy new image to ECS
        env:
          IMAGE_TAG: ${{ github.sha }}
        run: |
          aws ecs update-service \
            --cluster prod-cluster \
            --service hfm-app \
            --force-new-deployment \
            --region ${{ env.AWS_REGION }}

      - name: Wait for deployment to stabilise
        run: |
          aws ecs wait services-stable \
            --cluster prod-cluster \
            --services hfm-app \
            --region ${{ env.AWS_REGION }}

      - name: Notify team — success
        if: success()
        run: |
          aws sns publish \
            --topic-arn ${{ secrets.SNS_TOPIC_ARN }} \
            --message "Deployment successful — commit ${{ github.sha }}" \
            --subject "Deploy Success" \
            --region ${{ env.AWS_REGION }}

      - name: Notify team — failure
        if: failure()
        run: |
          aws sns publish \
            --topic-arn ${{ secrets.SNS_TOPIC_ARN }} \
            --message "DEPLOYMENT FAILED — commit ${{ github.sha }} — check pipeline logs at ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}" \
            --subject "Deploy FAILED" \
            --region ${{ env.AWS_REGION }}
```

---

## 9. GitHub Secrets Configuration

The pipeline reads sensitive values from GitHub Secrets — never from the YAML file itself.

Go to your GitHub repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add the following secrets:

| Secret name | Value | Where to find it |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | Your IAM access key | AWS Console → IAM → Users → Security credentials |
| `AWS_SECRET_ACCESS_KEY` | Your IAM secret key | Same as above — only shown once at creation |
| `SNS_TOPIC_ARN` | Your SNS topic ARN | Output from Step 1 in AWS Setup |

---

## 10. Running Locally for Testing

Before pushing to GitHub, always test scripts locally first.

### Test the Python script

```bash
# Install dependencies
pip install -r requirements.txt

# Create a test log directory with some old dummy files
mkdir -p /tmp/test-logs
touch -d "40 days ago" /tmp/test-logs/old_app.log
touch -d "5 days ago" /tmp/test-logs/recent_app.log

# Run the script (edit LOGS_DIR temporarily to /tmp/test-logs)
python3 scripts/disk_maintenance.py
```

### Run unit tests

```bash
pytest tests/ -v
```

### Lint Python

```bash
flake8 scripts/
```

### Lint Bash

```bash
shellcheck scripts/bootstrap.sh
```

---

## 11. Deployment Walkthrough

### First deployment — step by step

**Step 1** — Clone the repository

```bash
git clone https://github.com/your-username/aws-production-automation.git
cd aws-production-automation
```

**Step 2** — Run the AWS setup script to provision all required resources in one command:

```bash
# Edit the configuration block at the top first
bash scripts/aws_setup.sh
```

**Step 3** — Update the constants in `disk_maintenance.py` with your actual SNS ARN and region.

**Step 4** — Add GitHub Secrets (Section 9).

**Step 5** — Bootstrap your EC2 instance manually for the first time:

```bash
scp -i ~/.ssh/your-key.pem scripts/bootstrap.sh ubuntu@<EC2-IP>:/home/ubuntu/
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2-IP>
sudo bash bootstrap.sh
```

**Step 6** — Push code to trigger the pipeline:

```bash
git add .
git commit -m "feat: initial production automation setup"
git push origin main
```

**Step 7** — Watch the pipeline run in GitHub:

Go to your repository → **Actions** tab → click the running workflow.

You will see all three stages run sequentially. Green ticks mean success.

**Step 8** — Check your email for the SNS success notification.

---

## 12. Monitoring & Alerting

| What is monitored | How | Alert channel |
|---|---|---|
| Disk usage > 80% | `disk_maintenance.py` nightly cron | SNS email |
| Deployment success/failure | GitHub Actions `if: success()` / `if: failure()` | SNS email |
| Nginx service health | `systemctl status nginx` | Manual / CloudWatch |
| EC2 instance health | AWS ECS health checks | AWS Console |

To add CloudWatch alarms for CPU or memory:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "prod-high-cpu" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 85 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=i-xxxxxxxxxx \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:sns:eu-west-1:123456789012:ops-alerts \
  --region eu-west-1
```

---

## 13. Troubleshooting

### Bootstrap script fails

```bash
# Check the log for the exact error
sudo cat /var/log/bootstrap.log

# Most common cause: IAM permissions
# Verify the EC2 instance role has secretsmanager:GetSecretValue
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/ec2-role \
  --action-names secretsmanager:GetSecretValue
```

### Python script cannot connect to SNS

```bash
# Verify AWS credentials are configured
aws sts get-caller-identity

# Test SNS publish directly
aws sns publish \
  --topic-arn arn:aws:sns:eu-west-1:123456789012:ops-alerts \
  --message "Test alert" \
  --region eu-west-1
```

### GitHub Actions pipeline fails at AWS credentials step

- Double-check that `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are added correctly in GitHub Secrets (no spaces, no quotes around the value).
- Verify the IAM user has the required permissions.

### Nginx fails to start after bootstrap

```bash
# Check Nginx config for syntax errors
sudo nginx -t

# Check Nginx error logs
sudo journalctl -u nginx --no-pager -n 50
```

---

## 14. Security Considerations

- **No secrets in code** — all sensitive values are stored in AWS Secrets Manager or GitHub Secrets and fetched at runtime. No passwords, keys, or tokens exist in the scripts or pipeline YAML. This project uses a demo placeholder value in Secrets Manager to demonstrate this pattern — in a real deployment it would be replaced with actual credentials.
- **Least privilege IAM** — the EC2 instance role should only have `secretsmanager:GetSecretValue` for the specific secret paths it needs, not wildcard access.
- **Non-root application user** — the `appuser` created by bootstrap.sh has no login shell and no home directory, limiting blast radius if the application is compromised.
- **Firewall by default** — UFW blocks all ports except 22, 80, and 443. Nothing else is reachable.
- **Pipeline approval gate** — the deploy job uses `environment: production` in GitHub Actions, which can be configured to require a human approval before production deployments proceed.
- **Audit trail** — every script logs start time, each step, and completion time. Every pipeline run is recorded in GitHub Actions with full logs and the exact commit SHA that was deployed.

---

## Author

**Henry Kumah** — DevOps & Platform Engineer  
Belgrade, Serbia | [linkedin.com/in/henry-kumah](https://linkedin.com/in/henry-kumah) | [github.com/HenryKum23](https://github.com/HenryKum23)
