# Mastodon on AWS: hardened infrastructure as code

Terraform, Docker Compose and GitHub Actions for a single-server Mastodon instance
(EC2, S3 and CloudFront, ECR, SES, Cloudflare DNS). The project started as a cloud
engineering exercise and was then hardened step by step as a cloud security learning
project. This README records what the system is, what was changed to harden it, how each
change was checked, and what is still open.

**Domain:** mastodon.dpdns.org | **Region:** us-east-1 | **Server:** one EC2 t3.small with Docker Compose

> **Status.** All AWS resources have been destroyed and nothing is running. The code is
> kept so the stack can be rebuilt. The hardening described below was checked locally or in
> short-lived AWS labs, but **has not yet been run on a rebuilt server**. Read
> [Verification status](#10-verification-status) before relying on any claim here.
> The AWS account ID is deliberately not listed in this file.

---

## 1. Architecture

```
Visitors --DNS (Cloudflare, DNS only)--> Elastic IP --> EC2 (Ubuntu, 30 GB encrypted gp3)
                                                         |- Nginx :80/:443  (TLS from Let's Encrypt via certbot)
                                                         |- Mastodon web, streaming, sidekiq
                                                         |- PostgreSQL and Redis (internal Docker network only)
                                                         '- host cron: backup 02:00 UTC, Nginx reload 03:30 UTC

Media   --> S3 media bucket (private, CloudFront origin access control) --> CloudFront
Images  --> ECR (scan on push, keep last 3)  <-- GitHub Actions (OIDC, deploy role)
Email   --> SES (SMTP user)
Backups <-- server instance role (s3:PutObject only) -- S3 backup bucket
                                                         (private, encrypted, versioned, 30-day expiry)
```

| Piece | Purpose |
|---|---|
| EC2 + Docker Compose | Runs every Mastodon service on one server |
| S3 + CloudFront | Media storage and delivery; the bucket is not public |
| ECR | Container images, scanned on push |
| SES | Outgoing email |
| Cloudflare | DNS (records set to DNS only) |
| GitHub Actions + OIDC | Plans and deploys without any stored AWS key in GitHub |
| S3 backup bucket | The only off-server copy of the database dumps |

## 2. Project structure

```
mastodon-infra/
|- terraform/
|  |- bootstrap/              remote state bucket and lock table (uses LOCAL state; keep that file safe)
|  |- envs/prod/              run Terraform from here
|  '- modules/
|     |- aws-ec2/             instance, Elastic IP, key pair, cloud-init
|     |- aws-sg/              security group (22, 80, 443)
|     |- aws-iam/             OIDC provider, plan role, deploy role, server role, legacy app user
|     |- aws-s3-cloudfront/   media bucket and CDN
|     |- aws-s3-backup/       backup bucket
|     |- aws-ses/             email identity and SMTP user
|     '- aws-ecr/             container registries
|- compose/
|  |- docker-compose.yml      all services
|  |- nginx/                  reverse proxy and TLS (nginx.conf, nginx-bootstrap.conf)
|  '- .env.production.template
|- scripts/
|  |- 01-bootstrap-server.sh        run once after Terraform
|  |- 02-deploy-mastodon.sh         deploy; reuses saved secrets; optional RESTORE_FROM
|  |- 03-create-admin.sh            create the admin account
|  |- 04-upgrade.sh                 upgrade the Mastodon version
|  |- 05-backup.sh                  nightly PostgreSQL backup
|  |- 06-install-backup-cron.sh     installs the backup and Nginx-reload cron jobs
|  '- 07-check-cert.sh              certificate expiry check (run from OUTSIDE the server)
|- docs/restore-runbook.md          how to rebuild and restore
'- .github/workflows/              terraform.yml, deploy.yml, upgrade.yml, security-drift.yml
```

## 3. What was hardened

| Area | Problem found | Change made | How it was checked |
|---|---|---|---|
| Secrets in the repository | Real credentials were hardcoded in the deploy script and sat in public history | Script now reads them from environment variables and stops if any is missing; history rewritten with git filter-repo; repository deleted and recreated because GitHub kept serving the old commit by ID | Fresh clone: 0 AWS key patterns in all history; old commit URL returns 404 |
| Exposed keys | Keys were exposed publicly | Deactivated and deleted; CloudTrail Event history checked | No events found. Limits: 90 days, one region, no S3 object or SES SMTP events |
| GitHub to AWS trust | One role trusted any run from the repository (a wildcard) and carried broad write permissions | Exact-match trust conditions, two roles, trust strings use GitHub's real subject format with numeric owner and repository IDs | Five-situation lab with real tokens (section 4) |
| Terraform in CI | CI could apply infrastructure; roles used ecr:* and s3:* | Plan role is read-only plus state access; deploy role can only push to two ECR repositories; apply stays on the laptop; unused id-token permissions and the CI apply job removed | Plan reviews, policy simulator, lab |
| Deploy gate | Anyone who could push a branch could reach the deploy path | GitHub environment production limited to master with a required reviewer | Jobs from other branches and pull requests were refused by GitHub |
| Workflow bugs | Secret named GITHUB_REPO (not allowed), deploy gate checked main while the branch is master, upgrade used the wrong role | Use github.repository, gate on master, upgrade uses the deploy role | Diff review, YAML parse check |
| Silent server replacement | A newer Ubuntu image would force instance replacement and delete the database disk | lifecycle ignore_changes = [ami]; new images are adopted deliberately with -replace | Local lab; plan reading |
| Server identity | Long-lived keys in files | Instance role that can only s3:PutObject into the backup bucket; metadata service requires IMDSv2 with hop limit 1 | IAM policy simulator: put allowed, get and delete denied, other buckets denied; full plan shows the settings |
| Backups | Database lived on the instance disk with no copy | Nightly pg_dump, completeness check, UTC-stamped upload to a separate private, encrypted, versioned bucket with 30-day expiry and prevent_destroy | Local tests: success, failure (exit 1, no partial file), restore into a fresh database |
| Restore | No restore path; the deploy script generated new secret keys on every run | RESTORE_FROM option loads a dump into the empty database; psql uses ON_ERROR_STOP and --single-transaction; secret generation is idempotent (reuses the saved file) | Broken-dump test left nothing behind; harness test of the secrets branch |
| TLS renewal | Nginx never reloaded after renewal; certbot had no restart policy; smoke tests ignored certificate errors | certbot restart: always; daily Nginx reload cron; 07-check-cert.sh | Local lab reproduced the stale certificate and the reload fix |
| Terraform guards | A lifecycle block claimed to protect the server but did nothing | Replaced with ignore_changes; backup bucket protected with prevent_destroy | Code review |

## 4. Trust and permissions model

| Identity | Who or what uses it | Can | Cannot |
|---|---|---|---|
| Plan role | GitHub jobs on pull requests and pushes to master | Read-only access, read the Terraform state, write lock entries | Create, change or delete anything |
| Deploy role | GitHub jobs in the production environment | Log in to ECR, push images to two repositories | Pull, delete, touch S3 or CloudFront |
| Server role | The EC2 instance | s3:PutObject on the backup bucket | Read, list or delete backups |
| Admin login | You, from your laptop | Plan, apply, restore | Not used by any automation |
| Legacy app user | Mastodon (S3 and SES access) | See gaps | Long-lived keys are still created (section 9) |

Lab results for the GitHub roles (real tokens, checked in AWS):

| Situation | Plan role | Deploy role |
|---|---|---|
| Push to another branch | refused | refused |
| Pull request | accepted | refused |
| Push to master, no environment | accepted | refused |
| production environment from master | refused | accepted |
| production environment from another branch or a PR | blocked by GitHub | blocked by GitHub |

Limits: pull requests from forks get no token. A pull request run uses the workflow file
from that pull request. The plan role can read Terraform state, which can contain secrets.
If the repository is recreated its numeric IDs change; update the `github_oidc_repo`
default in `terraform/envs/prod/variables.tf` (verify with the GitHub API: read `owner.id` and `id`).

## 5. Backups and restore

- **Backup:** `scripts/05-backup.sh` dumps `mastodon_production` from the `mastodon_db` container, checks the dump finished, uploads it as `db/mastodon-<UTC timestamp>.sql.gz`, and deletes the local copy. `pipefail` and an error trap prevent empty or partial files.
- **Schedule:** `scripts/06-install-backup-cron.sh` writes `/etc/cron.d/mastodon-backup`: backup at 02:00 UTC (03:00 in Nigeria). Run it with `BACKUP_BUCKET=$(terraform output -raw backup_bucket_name) sudo -E ./06-install-backup-cron.sh`.
- **Retention:** current backups expire after 30 days, old versions after 7 days.
- **Targets:** RPO 24 hours, RTO 24 hours (the RTO is an estimate until a rebuild is rehearsed).
- **Irreplaceable secrets:** `SECRET_KEY_BASE`, the three `ACTIVE_RECORD_ENCRYPTION_*` values and the two `VAPID_*` keys. Copy them by hand into a password manager right after the first real deployment. Without the encryption values, encrypted data in a restored database cannot be read.
- **Restore:** done from your laptop with your own login (the server role cannot read). Full steps: [docs/restore-runbook.md](docs/restore-runbook.md).

## 6. TLS and certificates

- certbot renews every 12 hours when fewer than 30 days remain, using the webroot challenge (port 80 must stay open).
- Nginx reads certificates only at start, so a daily cron job (03:30 UTC) runs `docker exec mastodon_nginx nginx -s reload`.
- Check what visitors actually get, from outside the server: `scripts/07-check-cert.sh mastodon.dpdns.org 14` (exit 1 when fewer than 14 days remain). Not yet scheduled.
- `openssl s_client` shows the certificate without validating it; it will not catch a wrong hostname or a broken chain.

## 7. Deployment

**Prerequisites:** AWS admin login, Terraform 1.7 or newer, AWS CLI, a domain on Cloudflare, a GitHub repository, a password manager.

1. **Remote state.** In `terraform/bootstrap`: `terraform init`, `terraform plan -out=bootstrap.tfplan`, read it, `terraform apply bootstrap.tfplan`. This uses local state; keep that file.
2. **Variables.** Create `terraform/envs/prod/terraform.tfvars` (gitignored) with: `aws_region`, `aws_account_id`, `ssh_key_name`, `ssh_public_key_path`, `instance_type`, `mastodon_domain`, `mastodon_email`, `mastodon_version`, `github_repo`, `db_password`. Confirm the `github_oidc_repo` default matches the repository's numeric IDs.
3. **Infrastructure.** In `terraform/envs/prod`: `terraform init`, `terraform plan -out=prod.tfplan`. Read the summary line, then the list (any destroy or `-/+`?). Only then `terraform apply prod.tfplan`.
4. **GitHub.** Add the secrets in section 8. Create the environment `production`, limit it to `master`, require a reviewer, and store the deploy role ARN there as `DEPLOY_ROLE_ARN`.
5. **DNS.** Add the records from `terraform output cloudflare_dns_records` (DNS only).
6. **Server.** SSH in and run `scripts/01-bootstrap-server.sh`.
7. **Deploy.** Export the required variables (database password, app keys, SMTP login) and run `scripts/02-deploy-mastodon.sh`. A rebuilt server needs the saved secrets file in place first; to restore data also pass `RESTORE_FROM=/path/to/backup.sql.gz`.
8. **Save the secrets** into the password manager immediately.
9. **Admin and backups.** Run `scripts/03-create-admin.sh`, install the cron jobs (section 5), run `05-backup.sh` once by hand, and confirm an object appears in the backup bucket.
10. **Check TLS** from outside: `scripts/07-check-cert.sh mastodon.dpdns.org`.

**Teardown order:** `terraform plan -destroy` and read it; destroy `envs/prod` first; the backup bucket has `prevent_destroy` and holds versions, so flip the guard and empty it deliberately; remove the Cloudflare records (a record pointing at a released IP is a takeover risk); destroy `bootstrap` last, because the production state lives in its bucket.

## 8. GitHub Actions and secrets

| Workflow | Trigger | Identity | Purpose |
|---|---|---|---|
| terraform.yml | pull request, push to master, manual | plan role | Validate and plan only; applies happen from your laptop |
| deploy.yml | push to master touching compose or scripts, manual | production environment (SSH deploy) | Copy files to the server and reload services |
| upgrade.yml | manual | deploy role (production environment) | Push the new images to ECR, then upgrade over SSH |
| security-drift.yml | schedule, push, manual | plan role | Secret scan and drift checks. Disable it in the Actions tab while nothing is deployed; it is not reliable until its known problems are fixed |

| Secret | Used by | Notes |
|---|---|---|
| OIDC_ROLE_ARN | terraform.yml | Plan role ARN: `terraform output github_actions_role_arn` |
| DEPLOY_ROLE_ARN | upgrade.yml | Deploy role ARN; store as an **environment secret** in `production`. The module outputs it, but `envs/prod` does not expose it yet (section 9) |
| AWS_ACCOUNT_ID, MASTODON_DOMAIN, MASTODON_EMAIL, MASTODON_VERSION, DB_PASSWORD, SSH_PUBLIC_KEY | terraform.yml | Inputs for the plan |
| SSH_PRIVATE_KEY, EC2_PUBLIC_IP | deploy.yml, upgrade.yml | Used for the SSH deploy path |

Names starting with `GITHUB_` are not allowed as secret names. The old `GITHUB_REPO` and `REPO_NAME` secrets are unused. Do not store AWS access keys in GitHub: authentication is by OIDC.

## 9. Known gaps and next steps

1. SSH (port 22) is open to 0.0.0.0/0, and the deploy workflow does not check the host key.
2. CloudFront uses the default certificate, so its minimum protocol version is TLSv1.
3. Long-lived IAM access keys are still created for the app and SES users, and their secrets land in Terraform state.
4. The backup bucket lives in the same Terraform stack as the server; it should outlive it.
5. The full rebuild on AWS has never been rehearsed, so the 24-hour RTO is not measured.
6. Nothing alerts on a failed backup or an approaching certificate expiry, and `07-check-cert.sh` is not scheduled.
7. `envs/prod` does not output the deploy role ARN, so it must be copied from the AWS console until an output is added.
8. PostgreSQL 14 reaches end of life in November 2026 (verify before relying on it); test restores into the new version when upgrading.
9. Container images and GitHub Actions are not pinned. CI pins Terraform 1.7.0 while local runs are newer.
10. Housekeeping: unused variables (`github_repo`, `db_password`) in the IAM module and prod, the obsolete `version:` line in the compose file, and the name of `06-install-backup-cron.sh` (it now installs two jobs).

## 10. Verification status

| Item | Status |
|---|---|
| Deploy script secrets handling, backup script (success, failure, restore), broken-dump restore, certificate reload behaviour, cron file rendering, compose validation | **Tested locally** |
| GitHub trust policies for both roles, server role permissions | **Verified in AWS** in short-lived labs (real tokens, policy simulator), then destroyed |
| Full Terraform plan of the whole stack (40 resources, all creates) | **Read-only plan** with placeholder values |
| Full rebuild, backup upload from the real server role, restore on a new server, certificate renewal and reload on the real server, scheduled workflows | **Untested** |

## 11. Cost notes

Costs depend on usage and AWS prices change; check current pricing before deploying. The
ongoing items are the EC2 instance, its Elastic IP and 30 GB disk, S3 storage, CloudFront
and SES. The design avoids NAT gateways, load balancers and managed databases. After a teardown,
check for leftover Elastic IPs, volumes, snapshots and buckets.

## 12. More material

- [docs/restore-runbook.md](docs/restore-runbook.md): step-by-step rebuild and restore, with its own list of untested items.
- Git remote: `git remote add origin https://github.com/christopherchidera200-lab/mastodon-infra.git`
