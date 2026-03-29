#!/bin/bash
# =============================================================
# Script:       bootstrap.sh
# Description:  Configures a fresh Ubuntu EC2 server —
#               installs packages, creates app user, fetches
#               secret, configures Nginx, sets firewall rules.
#               Runs automatically on first boot via EC2
#               user-data passed by aws_setup.sh at launch time.
#               No manual SSH required.
# Author:       Henry Kumah
# Created:      2026-03-01
# Version:      1.1
# Usage:        Automatic via EC2 user-data (see aws_setup.sh)
#               Manual fallback: sudo bash bootstrap.sh
# Dependencies: AWS CLI configured with appropriate IAM
#               permissions (secretsmanager:GetSecretValue)
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
apt-get install -y nginx awscli curl unzip docker.io

# Enable Docker so it starts on reboot
systemctl enable docker
systemctl start docker

# ── 3. Create application user ────────────────────────────────
echo "[3/6] Creating application user..."
useradd --system --no-create-home --shell /usr/sbin/nologin appuser

# Add ubuntu user to docker group so pipeline SSH deploys can run docker
usermod -aG docker ubuntu

# ── 4. Fetch demo secret from AWS Secrets Manager ─────────────
# This project contains no real application credentials.
# This step demonstrates the production pattern of fetching a
# secret at runtime. In a real deployment, replace the secret
# path with your actual secret and use the fetched value where
# your application needs it — for example, passed as an
# environment variable to a Docker container on startup.
# The fetch mechanism is identical regardless of what the
# secret contains.
echo "[4/6] Fetching secret from AWS Secrets Manager..."
APP_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id prod/app/secret \
  --query SecretString \
  --output text \
  --region eu-west-1)
echo "      Secret fetched successfully."

# ── 5. Configure Nginx ────────────────────────────────────────
# Nginx listens on port 80 and proxies all traffic to the
# Docker container running on port 8080 on the same server.
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
# Only ports 22 (SSH), 80 (HTTP), and 443 (HTTPS) are open.
# Everything else is blocked by default.
echo "[6/6] Configuring firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "=== Bootstrap complete: $(date) ==="

# NB: What makes this production-grade isn't just the commands — it's set -euo pipefail at the top. 
# If any command fails, the whole script stops immediately rather than silently continuing in a broken state.