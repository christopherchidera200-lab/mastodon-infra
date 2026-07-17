#!/bin/bash
# =============================================================
# SCRIPT 02 — Deploy Mastodon
# Run on EC2 server after filling in all variables below
# Usage: bash /opt/mastodon/scripts/02-deploy-mastodon.sh
# =============================================================

set -euo pipefail

# ── FILL IN THESE VALUES (from terraform output) ─────────────
AWS_ACCOUNT_ID="873871686800"
AWS_REGION="us-east-1"
AWS_ACCESS_KEY_ID="AKIA4W5WPXSIHCQIPBMR"           # terraform output aws_access_key_id
AWS_SECRET_ACCESS_KEY="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"       # terraform output -raw aws_secret_access_key
S3_BUCKET="mastodon-media-a1aa3081"                   # terraform output s3_bucket_name
S3_ALIAS_HOST="d2vdneyktx6iep.cloudfront.net"              # terraform output cloudfront_domain
SMTP_LOGIN="AKIA4W5WPXSIIUHUE3L4"                  # terraform output ses_smtp_username
SMTP_PASSWORD="BNlvAXleFwb/vesFJPbSC8mKLG+T+CWAwzu/hZvwkq2D"              # terraform output -raw ses_smtp_password
DB_PASSWORD="Chrisnwolisa29."          
export DB_PASSWORD
MASTODON_VERSION="v4.6.2"
DOMAIN="mastodon.dpdns.org"
ADMIN_EMAIL="christopherchidera200@gmail.com"

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_WEB_IMAGE="${ECR_REGISTRY}/mastodon/web:${MASTODON_VERSION}"
ECR_STREAMING_IMAGE="${ECR_REGISTRY}/mastodon/streaming:${MASTODON_VERSION}"
export ECR_WEB_IMAGE ECR_STREAMING_IMAGE
echo "============================================"
echo "Mastodon Deployment — Script 02"
echo "Domain: ${DOMAIN}"
echo "Version: ${MASTODON_VERSION}"
echo "============================================"

# ── Step 1: Login to ECR ─────────────────────────────────────
echo "[1/9] Logging into ECR..."
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
echo "ECR login ✅"

# ── Step 2: Pull and push Mastodon images to ECR ─────────────
echo "[2/9] Pulling Mastodon images from GHCR..."
docker pull ghcr.io/mastodon/mastodon:${MASTODON_VERSION}
docker pull ghcr.io/mastodon/mastodon-streaming:${MASTODON_VERSION}

echo "Pushing to ECR..."
docker tag ghcr.io/mastodon/mastodon:${MASTODON_VERSION} "${ECR_WEB_IMAGE}"
docker push "${ECR_WEB_IMAGE}"

docker tag ghcr.io/mastodon/mastodon-streaming:${MASTODON_VERSION} "${ECR_STREAMING_IMAGE}"
docker push "${ECR_STREAMING_IMAGE}"
echo "Images in ECR ✅"

# ── Step 3: Generate Mastodon secrets ─────────────────────────
echo "[3/9] Generating Mastodon application secrets..."
SECRET_KEY_BASE=$(docker run --rm "${ECR_WEB_IMAGE}" bundle exec rails secret)

AR_KEYS=$(docker run --rm "${ECR_WEB_IMAGE}" bin/rails db:encryption:init)
AR_PRIMARY_KEY=$(echo "${AR_KEYS}"         | grep "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY="         | cut -d= -f2)
AR_DETERMINISTIC_KEY=$(echo "${AR_KEYS}"   | grep "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY="   | cut -d= -f2)
AR_KEY_DERIVATION_SALT=$(echo "${AR_KEYS}" | grep "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=" | cut -d= -f2)

VAPID_KEYS=$(docker run --rm "${ECR_WEB_IMAGE}" bundle exec rails mastodon:webpush:generate_vapid_key)
VAPID_PRIVATE_KEY=$(echo "${VAPID_KEYS}" | grep "VAPID_PRIVATE_KEY" | cut -d= -f2)
VAPID_PUBLIC_KEY=$(echo "${VAPID_KEYS}"  | grep "VAPID_PUBLIC_KEY"  | cut -d= -f2)

# Save secrets to file
cat > /opt/mastodon/secrets/mastodon-secrets-KEEP-SAFE.txt << SECRETS
# MASTODON SECRETS — GENERATED $(date)
# BACK THIS UP. DO NOT LOSE THESE. DO NOT COMMIT TO GITHUB.
SECRET_KEY_BASE=${SECRET_KEY_BASE}
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${AR_PRIMARY_KEY}
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${AR_DETERMINISTIC_KEY}
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${AR_KEY_DERIVATION_SALT}
VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}
VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}
DB_PASSWORD=${DB_PASSWORD}
SECRETS
chmod 600 /opt/mastodon/secrets/mastodon-secrets-KEEP-SAFE.txt
echo "Secrets generated and saved to /opt/mastodon/secrets/mastodon-secrets-KEEP-SAFE.txt ✅"

# ── Step 4: Create .env.production ───────────────────────────
echo "[4/9] Creating .env.production..."
cat > /opt/mastodon/compose/.env.production << ENV
LOCAL_DOMAIN=${DOMAIN}
RAILS_ENV=production
NODE_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true

SECRET_KEY_BASE=${SECRET_KEY_BASE}
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${AR_PRIMARY_KEY}
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${AR_DETERMINISTIC_KEY}
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${AR_KEY_DERIVATION_SALT}

DB_HOST=db
DB_PORT=5432
DB_NAME=mastodon_production
DB_USER=mastodon
DB_PASS=${DB_PASSWORD}

REDIS_HOST=redis
REDIS_PORT=6379

S3_ENABLED=true
S3_BUCKET=${S3_BUCKET}
S3_REGION=us-east-1
S3_PROTOCOL=https
S3_ALIAS_HOST=${S3_ALIAS_HOST}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}

SMTP_SERVER=email-smtp.us-east-1.amazonaws.com
SMTP_PORT=587
SMTP_LOGIN=${SMTP_LOGIN}
SMTP_PASSWORD=${SMTP_PASSWORD}
SMTP_FROM_ADDRESS=notifications@${DOMAIN}
SMTP_AUTH_METHOD=plain
SMTP_OPENSSL_VERIFY_MODE=none
SMTP_ENABLE_STARTTLS=auto

VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}
VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}

ES_ENABLED=false
http_hidden_proxy=http://privoxy:8118
ALLOW_ACCESS_TO_HIDDEN_SERVICE=true

WEB_CONCURRENCY=1
MAX_THREADS=5
SIDEKIQ_CONCURRENCY=5
PREPARED_STATEMENTS=false

IP_RETENTION_PERIOD=31556952
SESSION_RETENTION_PERIOD=31556952

DB_PASSWORD=${DB_PASSWORD}
ENV
chmod 600 /opt/mastodon/compose/.env.production
echo ".env.production created ✅"

# ── Step 5: Copy compose files ────────────────────────────────
echo "[5/9] Setting up Docker Compose files..."
cp /opt/mastodon/compose/docker-compose.yml /opt/mastodon/compose/docker-compose.yml 2>/dev/null || true

# Write ECR image URLs into compose env
cat >> /opt/mastodon/compose/.env.production << COMPOSEENV
ECR_WEB_IMAGE=${ECR_WEB_IMAGE}
ECR_STREAMING_IMAGE=${ECR_STREAMING_IMAGE}
COMPOSEENV

# Create the .env file Docker Compose actually reads for ${...} substitution
# (env_file: on services only injects vars INSIDE containers — this is separate)
cat > /opt/mastodon/compose/.env << ENVFILE
ECR_WEB_IMAGE=${ECR_WEB_IMAGE}
ECR_STREAMING_IMAGE=${ECR_STREAMING_IMAGE}
DB_PASSWORD=${DB_PASSWORD}
ENVFILE
chmod 600 /opt/mastodon/compose/.env

echo "Docker Compose ready ✅"

# ── Step 6: Issue TLS certificate (HTTP must work first) ──────
echo "[6/9] Starting nginx in bootstrap mode (HTTP only, no cert yet)..."
cd /opt/mastodon/compose

# Swap in the bootstrap config (no SSL block, so nginx can start with zero certs)
cp nginx/nginx.conf nginx/nginx-full.conf.bak
cp nginx/nginx-bootstrap.conf nginx/nginx.conf

docker compose up -d nginx
sleep 10

echo "Requesting Let's Encrypt certificate for ${DOMAIN}..."
docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email "${ADMIN_EMAIL}" \
  --agree-tos \
  --no-eff-email \
  -d "${DOMAIN}"echo "TLS certificate issued ✅"

# Swap the real SSL-enabled config back in now that certs exist
echo "Switching nginx to full HTTPS config..."
cp nginx/nginx-full.conf.bak nginx/nginx.conf
docker compose restart nginx
echo "Nginx running with HTTPS ✅"
# ── Step 7: Initialise database ───────────────────────────────
echo "[7/9] Starting database and running migrations..."
docker compose up -d db redis
echo "Waiting 30 seconds for PostgreSQL to be ready..."
sleep 30

docker compose run --rm web bundle exec rails db:setup
echo "Database initialised ✅"

# ── Step 8: Start all services ────────────────────────────────
echo "[8/9] Starting all Mastodon services..."
docker compose up -d
echo "Waiting 60 seconds for services to stabilise..."
sleep 60

echo "Service status:"
docker compose ps

# ── Step 9: Smoke test ────────────────────────────────────────
echo "[9/9] Running smoke tests..."
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health)
if [ "${HEALTH}" = "200" ]; then
  echo "Web health check ✅  (HTTP 200)"
else
  echo "Web health check ⚠️  (HTTP ${HEALTH}) — check: docker compose logs web"
fi

STREAM=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/api/v1/streaming/health)
if [ "${STREAM}" = "200" ]; then
  echo "Streaming health check ✅  (HTTP 200)"
else
  echo "Streaming health check ⚠️  (HTTP ${STREAM}) — check: docker compose logs streaming"
fi

echo ""
echo "============================================"
echo "Deployment complete ✅"
echo "Next: run scripts/03-create-admin.sh"
echo "Then visit: https://${DOMAIN}"
echo "============================================"
