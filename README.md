# Mastodon Infrastructure — AWS + Docker Compose
**Domain:** mastodon.dpdns.org | **AWS Account:** 873871686800 | **Region:** us-east-1
**Compute:** AWS EC2 t3.small | **Runtime:** Docker Compose | **Cost:** ~$0 (AWS credits)

## Project Structure
```
mastodon-infra/
├── terraform/
│   ├── envs/prod/          ← run terraform from here
│   └── modules/
│       ├── aws-ec2/        ← t3.small instance + Elastic IP
│       ├── aws-sg/         ← security group (22, 80, 443)
│       ├── aws-iam/        ← OIDC + app IAM user
│       ├── aws-s3-cloudfront/ ← media storage + CDN
│       ├── aws-ses/        ← email
│       └── aws-ecr/        ← container image registry
├── compose/
│   ├── docker-compose.yml  ← all Mastodon services
│   ├── nginx/nginx.conf    ← reverse proxy + TLS
│   └── .env.production.template ← copy and fill in
├── scripts/
│   ├── 01-bootstrap-server.sh  ← run once after terraform
│   ├── 02-deploy-mastodon.sh   ← main deployment
│   ├── 03-create-admin.sh      ← create admin account
│   └── 04-upgrade.sh           ← upgrade Mastodon version
└── .github/workflows/
    ├── terraform.yml       ← infra plan + apply
    ├── deploy.yml          ← deploy to EC2
    ├── upgrade.yml         ← version upgrade
    └── security-drift.yml  ← daily security checks
```

## Deployment Order
```
Phase 1: terraform apply          → provisions AWS resources
Phase 2: GitHub Secrets           → add all 15 secrets
Phase 3: SSH + script 01          → bootstrap EC2 server
Phase 4: Cloudflare DNS           → add DNS records
Phase 5: script 02                → deploy Mastodon
Phase 6: script 03                → create admin account
```

## GitHub Secrets Required
```
AWS_ACCOUNT_ID        873871686800
OIDC_ROLE_ARN         from: terraform output github_actions_role_arn
SSH_PUBLIC_KEY        contents of mastodon_key.pub
SSH_PRIVATE_KEY       contents of mastodon_key (needed for deploy pipeline)
EC2_PUBLIC_IP         from: terraform output ec2_public_ip
MASTODON_DOMAIN       mastodon.dpdns.org
MASTODON_EMAIL        christopherchidera200@gmail.com
MASTODON_VERSION      v4.6.2
GITHUB_REPO           christopherchidera200-lab/mastodon
DB_PASSWORD           your chosen database password
```

## Git Remote
```
git remote add origin https://github.com/christopherchidera200-lab/mastodon.git
```
