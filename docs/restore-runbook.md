# Mastodon restore runbook

Goal: rebuild the server and restore the latest backup. Targets: RPO 24 hours, RTO 24 hours.

## Status: what has and hasn't been tested
- Tested locally: nightly dump script (`scripts/05-backup.sh`), restore into an empty database, the
  secrets-reuse branch of `02-deploy-mastodon.sh`, and a broken dump failing cleanly.
- NOT tested: the full rebuild on AWS. Until it has been rehearsed once, the 24-hour RTO is an estimate.

## You need before you start
1. Your admin AWS login on your laptop. The server's own role cannot list or read backups, by design.
2. The password-manager entry holding the six irreplaceable keys: `SECRET_KEY_BASE`, the three
   `ACTIVE_RECORD_ENCRYPTION_*` values, and `VAPID_PRIVATE_KEY` / `VAPID_PUBLIC_KEY`.
3. The domain's DNS access (Cloudflare).

## Steps
1. Get the newest backup (from your laptop, admin login):
   - `aws s3 ls s3://<backup-bucket>/db/` and pick the newest `mastodon-<UTC timestamp>.sql.gz`
   - `aws s3 cp s3://<backup-bucket>/db/<file> .`
   - Check it: `gzip -dc <file> | tail -n 5 | grep "dump complete"`
2. Recreate the state bucket if it no longer exists: apply `terraform/bootstrap/` first.
3. Rebuild the infrastructure: in `terraform/envs/prod`, `terraform init`, then `terraform plan -out=...`.
   Read the plan (counts, any `-/+`) BEFORE applying. Never apply blind.
4. Update DNS records in Cloudflare to the new server IP and the new CloudFront / SES values.
5. Put the secrets back BEFORE running the deploy script:
   - create `/opt/mastodon/secrets/`, write `mastodon-secrets-KEEP-SAFE.txt` from the password manager,
     `chmod 600` it. The deploy script then reuses these keys instead of generating new ones.
6. Copy the dump to the server, then run `01-bootstrap-server.sh`, then
   `RESTORE_FROM=/home/ubuntu/<file> ./02-deploy-mastodon.sh` (it stops and names any missing variable).
7. Verify: `/health` returns 200, you can log in, a known old post exists, an old image loads, a test email arrives.
8. Re-install backups: `BACKUP_BUCKET=<name> sudo -E ./06-install-backup-cron.sh`, run `05-backup.sh` once by hand,
   and confirm a new object appears in the bucket.
9. Write down the elapsed time here: Last tested: (never). Measured RTO: (unknown).

## Known gaps
- Rebuild on AWS never rehearsed end to end.
- The backup bucket is in the same Terraform stack as the server; it should live in its own stack.
- Secrets backup is manual (password manager). If the entry is missing, encrypted data cannot be recovered.
- Redis is not backed up (cache and queues only).
- Nothing alerts you if the nightly backup fails. Check the log until monitoring exists.
- PostgreSQL 14 reaches end of life in November 2026; plan an upgrade and test restores into the new version.
