#!/usr/bin/env bash
# Installs the nightly backup job. Run once on the server:
#   BACKUP_BUCKET=$(terraform output -raw backup_bucket_name) sudo -E ./06-install-backup-cron.sh
set -euo pipefail

: "${BACKUP_BUCKET:?export BACKUP_BUCKET (terraform output backup_bucket_name) first}"
CRON_FILE="${CRON_FILE:-/etc/cron.d/mastodon-backup}"
SCRIPT="${SCRIPT:-/opt/mastodon/scripts/05-backup.sh}"
LOG="${LOG:-/home/ubuntu/mastodon-backup.log}"

umask 022
cat > "${CRON_FILE}" << CRON
# Managed by scripts/06-install-backup-cron.sh. Edit that script, not this file.
PATH=/usr/local/bin:/usr/bin:/bin
BACKUP_BUCKET=${BACKUP_BUCKET}
# 02:00 UTC = 03:00 in Nigeria (UTC+1, no daylight saving)
0 2 * * * ubuntu ${SCRIPT} >> ${LOG} 2>&1
CRON
chmod 644 "${CRON_FILE}"
echo "Installed ${CRON_FILE}"
