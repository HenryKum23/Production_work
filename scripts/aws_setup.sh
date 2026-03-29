#!/bin/bash
# =============================================================
# Script:       aws_setup.sh
# Description:  Provisions all required AWS resources for this
#               project in one run — SNS, Secrets Manager,
#               ECR, and EC2
# Author:       Henry Kumah
# Created:      2026-03-01
# Version:      1.1
# Usage:        bash scripts/aws_setup.sh
# Dependencies: AWS CLI v2 configured with appropriate IAM
#               permissions
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