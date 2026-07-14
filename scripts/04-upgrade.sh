#!/bin/bash
# =============================================================
# SCRIPT 04 — Upgrade Mastodon to a new version
# Usage: bash scripts/04-upgrade.sh v4.7.0
# =============================================================

set -euo pipefail

NEW_VERSION="${1:-}"
if [ -z "${NEW_VERSION}" ]; then
  echo "Usage: bash 04-upgrade.sh v4.7.0"
  exit 1
fi

AWS_ACCOUNT_ID="873871686800"
AWS_REGION="us-east-1"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_WEB_IMAGE="${ECR_REGISTRY}/mastodon/web:${NEW_VERSION}"
ECR_STREAMING_IMAGE="${ECR_REGISTRY}/mastodon/streaming:${NEW_VERSION}"

echo "============================================"
echo "Upgrading Mastodon to ${NEW_VERSION}"
echo "============================================"

cd /opt/mastodon/compose

echo "[1/5] Pulling new images from GHCR..."
docker pull ghcr.io/mastodon/mastodon:${NEW_VERSION}
docker pull ghcr.io/mastodon/mastodon-streaming:${NEW_VERSION}

echo "[2/5] Pushing to ECR..."
docker tag ghcr.io/mastodon/mastodon:${NEW_VERSION} "${ECR_WEB_IMAGE}"
docker push "${ECR_WEB_IMAGE}"
docker tag ghcr.io/mastodon/mastodon-streaming:${NEW_VERSION} "${ECR_STREAMING_IMAGE}"
docker push "${ECR_STREAMING_IMAGE}"

echo "[3/5] Running database migrations..."
ECR_WEB_IMAGE="${ECR_WEB_IMAGE}" \
ECR_STREAMING_IMAGE="${ECR_STREAMING_IMAGE}" \
docker compose run --rm web bundle exec rails db:migrate

echo "[4/5] Restarting services with new images..."
ECR_WEB_IMAGE="${ECR_WEB_IMAGE}" \
ECR_STREAMING_IMAGE="${ECR_STREAMING_IMAGE}" \
docker compose up -d --force-recreate web streaming sidekiq

echo "[5/5] Verifying health..."
sleep 30
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health)
if [ "${HEALTH}" = "200" ]; then
  echo "Upgrade to ${NEW_VERSION} complete ✅"
  # Update .env.production with new version
  sed -i "s|mastodon/web:v[0-9.]*|mastodon/web:${NEW_VERSION}|g" .env.production
else
  echo "Health check failed (${HEALTH}) — rolling back..."
  docker compose up -d --force-recreate web streaming sidekiq
  echo "Rollback complete"
  exit 1
fi
