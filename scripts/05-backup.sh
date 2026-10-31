#!/usr/bin/env bash
# Nightly PostgreSQL backup for Mastodon.
# Runs on the HOST (not inside a container) so it can use the instance role.
set -euo pipefail

BACKUP_BUCKET="${BACKUP_BUCKET:-}"       # empty = keep the file locally (testing)
BACKUP_DIR="${BACKUP_DIR:-${HOME}/mastodon-backups}"
DB_CONTAINER="${DB_CONTAINER:-mastodon_db}"
DB_USER="${DB_USER:-mastodon}"
DB_NAME="${DB_NAME:-mastodon_production}"

STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
FILE="${BACKUP_DIR}/mastodon-${STAMP}.sql.gz"

umask 077                                 # new files readable by owner only
mkdir -p "${BACKUP_DIR}"
trap 'rm -f "${FILE}"' ERR                # never leave a partial file behind

echo "Dumping ${DB_NAME} ..."
docker exec "${DB_CONTAINER}" pg_dump -U "${DB_USER}" "${DB_NAME}" | gzip > "${FILE}"

# A dump is only a backup if it finished. pg_dump writes this line last.
if ! gzip -dc "${FILE}" | tail -n 5 | grep -q "dump complete"; then
  echo "ERROR: dump is incomplete, discarding" >&2
  rm -f "${FILE}"
  exit 1
fi

if [ -n "${BACKUP_BUCKET}" ]; then
  aws s3 cp "${FILE}" "s3://${BACKUP_BUCKET}/db/$(basename "${FILE}")" --only-show-errors
  echo "Uploaded to s3://${BACKUP_BUCKET}/db/$(basename "${FILE}")"
  rm -f "${FILE}"                         # keep the server's 30 GB disk clean
else
  echo "BACKUP_BUCKET not set: kept locally at ${FILE}"
fi
