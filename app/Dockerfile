# =============================================================
# File:         Dockerfile
# Description:  Builds the application container image.
#               The app runs on port 8080 inside the container.
#               Nginx on the EC2 host proxies port 80 to 8080.
# Author:       Henry Kumah
# Created:      2026-03-01
# Version:      1.0
# Usage:        Built and pushed to ECR by the CI/CD pipeline.
#               docker build -t hfm-app .
#               docker run -p 8080:8080 hfm-app
# =============================================================

# ── Base image ────────────────────────────────────────────────
# Official Python slim image — smaller than the full image,
# no unnecessary packages included
FROM python:3.11-slim

# ── Working directory ─────────────────────────────────────────
# All subsequent commands run from this directory inside
# the container
WORKDIR /app

# ── Install dependencies ──────────────────────────────────────
# Copy requirements first — Docker caches this layer separately.
# If only app code changes, this layer is not rebuilt,
# making builds significantly faster.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Copy application code ─────────────────────────────────────
COPY . .

# ── Create a non-root user to run the app ─────────────────────
# Never run application processes as root inside a container.
# If the app is compromised, the attacker only has limited
# permissions — not full root access to the container.
RUN useradd --system --no-create-home --shell /usr/sbin/nologin appuser
USER appuser

# ── Expose the application port ───────────────────────────────
# The app listens on 8080 inside the container.
# Nginx on the host proxies port 80 traffic to this port.
EXPOSE 8080

# ── Start the application ─────────────────────────────────────
CMD ["python3", "app/main.py"]