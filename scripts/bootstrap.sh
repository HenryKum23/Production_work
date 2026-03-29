#!/bin/bash
# =============================================================
# Script:      bootstrap.sh
# Description: Provisions and configures a fresh Ubuntu server
# Author:      Henry Kumah
# Created:     2024-01-15
# Last Modified: 2024-03-10
# Version:     1.3
# Usage:       sudo bash bootstrap.sh
# ============================================================

# bootstrap.sh — run once on a fresh Ubuntu server

set -euo pipefail   # stop on any error, treat unset vars as errors

LOG="/var/log/bootstrap.log"
exec >> "$LOG" 2>&1  # all output goes to log file

echo "=== Bootstrap started: $(date) ==="

# 1. Update OS packages
apt-get update -y && apt-get upgrade -y

# 2. Install required packages
apt-get install -y nginx postgresql-client awscli curl unzip

# 3. Create application user (no login shell, for security)
useradd --system --no-create-home --shell /usr/sbin/nologin appuser

# 4. Pull app config from AWS Secrets Manager
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id prod/db/password \
  --query SecretString \
  --output text)

# 5. Write Nginx config
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

# 6. Set firewall rules
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS
ufw --force enable

echo "=== Bootstrap complete: $(date) ==="

# NB: What makes this production-grade isn't just the commands — it's set -euo pipefail at the top. 
# If any command fails, the whole script stops immediately rather than silently continuing in a broken state.