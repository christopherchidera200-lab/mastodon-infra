#!/bin/bash
# =============================================================
# SCRIPT 01 — Bootstrap EC2 server
# Run this ONCE after terraform apply
# SSH into the server and run: bash /opt/mastodon/scripts/01-bootstrap-server.sh
# =============================================================

set -euo pipefail

echo "============================================"
echo "Mastodon EC2 Bootstrap — Script 01"
echo "============================================"

# ── Wait for cloud-init to finish ────────────────────────────
echo "[1/5] Waiting for cloud-init to finish..."
cloud-init status --wait
echo "Cloud-init complete ✅"

# ── Verify Docker installed ───────────────────────────────────
echo "[2/5] Verifying Docker..."
docker --version
docker compose version
echo "Docker ready ✅"

# ── Verify swap is active ─────────────────────────────────────
echo "[3/5] Verifying swap..."
free -h
SWAP=$(swapon --show | wc -l)
if [ "$SWAP" -lt 1 ]; then
  echo "Swap not found — creating manually..."
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
echo "Swap active ✅"

# ── Create app directories ────────────────────────────────────
echo "[4/5] Creating app directories..."
mkdir -p /opt/mastodon/{compose/nginx,scripts,secrets}
chmod 700 /opt/mastodon/secrets
echo "Directories ready ✅"

# ── Install AWS CLI v2 ────────────────────────────────────────
echo "[5/5] Verifying AWS CLI..."
if ! command -v aws &>/dev/null; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install
  rm -rf /tmp/awscliv2.zip /tmp/aws
fi
aws --version
echo "AWS CLI ready ✅"

echo ""
echo "============================================"
echo "Bootstrap complete ✅"
echo "Next: run scripts/02-deploy-mastodon.sh"
echo "============================================"
