#!/bin/bash
# =============================================================
# SCRIPT 03 — Create Mastodon admin account
# Run after 02-deploy-mastodon.sh completes successfully
# =============================================================

set -euo pipefail

ADMIN_USERNAME="christopher"
ADMIN_EMAIL="christopherchidera200@gmail.com"

echo "============================================"
echo "Creating Mastodon admin account"
echo "Username: ${ADMIN_USERNAME}"
echo "Email:    ${ADMIN_EMAIL}"
echo "============================================"

cd /opt/mastodon/compose

# Create account and confirm email in one step
docker compose exec web bin/tootctl accounts create \
  "${ADMIN_USERNAME}" \
  --email "${ADMIN_EMAIL}" \
  --confirmed \
  --role Owner
echo ""
echo "============================================"
echo "Admin account created ✅"
echo ""
echo "Login at: https://mastodon.dpdns.org"
echo "Username: ${ADMIN_USERNAME}"
echo "Email:    ${ADMIN_EMAIL}"
echo ""
echo "Set your password via forgot password flow"
echo "or check your email for the welcome message"
echo "============================================"
