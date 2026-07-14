# ── EC2 ──────────────────────────────────────────────────────
output "ec2_public_ip" {
  description = "SSH into this IP to deploy Mastodon"
  value       = module.aws_ec2.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS of EC2 instance"
  value       = module.aws_ec2.public_dns
}

# ── S3 + CloudFront ───────────────────────────────────────────
output "s3_bucket_name" {
  description = "Add to .env.production as S3_BUCKET"
  value       = module.aws_s3_cloudfront.bucket_name
}

output "cloudfront_domain" {
  description = "Add to .env.production as S3_ALIAS_HOST"
  value       = module.aws_s3_cloudfront.cloudfront_domain
}

# ── SES ───────────────────────────────────────────────────────
output "ses_smtp_username" {
  description = "Add to .env.production as SMTP_LOGIN"
  value       = module.aws_ses.smtp_username
}

output "ses_smtp_password" {
  description = "Add to .env.production as SMTP_PASSWORD"
  value       = module.aws_ses.smtp_password
  sensitive   = true
}

output "ses_dkim_tokens" {
  description = "Add 3 CNAME records in Cloudflare DNS"
  value       = module.aws_ses.dkim_tokens
}

output "ses_verification_token" {
  description = "Add TXT record _amazonses in Cloudflare DNS"
  value       = module.aws_ses.domain_verification_token
}

# ── ECR ───────────────────────────────────────────────────────
output "ecr_web_url" {
  description = "Mastodon web image URL in ECR"
  value       = module.aws_ecr.web_repo_url
}

output "ecr_streaming_url" {
  description = "Mastodon streaming image URL in ECR"
  value       = module.aws_ecr.streaming_repo_url
}

# ── IAM / OIDC ───────────────────────────────────────────────
output "github_actions_role_arn" {
  description = "Add as OIDC_ROLE_ARN in GitHub Secrets"
  value       = module.aws_iam.github_actions_role_arn
}

output "aws_access_key_id" {
  description = "Add to .env.production as AWS_ACCESS_KEY_ID"
  value       = module.aws_iam.access_key_id
}

output "aws_secret_access_key" {
  description = "Add to .env.production as AWS_SECRET_ACCESS_KEY"
  value       = module.aws_iam.secret_access_key
  sensitive   = true
}

# ── Cloudflare DNS records summary ───────────────────────────
output "cloudflare_dns_records" {
  description = "Add these records in Cloudflare dashboard"
  value       = <<-EOT
    ============================================================
    CLOUDFLARE DNS RECORDS — add these manually
    dash.cloudflare.com → mastodon.dpdns.org → DNS
    ============================================================
    Type   Name     Value                          Proxy
    A      @        ${module.aws_ec2.public_ip}    DNS only (grey)
    A      www      ${module.aws_ec2.public_ip}    DNS only (grey)
    CNAME  files    ${module.aws_s3_cloudfront.cloudfront_domain}  DNS only (grey)

    SES records (get token values from ses_dkim_tokens output):
    TXT    _amazonses.<domain>   → ses_verification_token value
    CNAME  TOKEN1._domainkey     → TOKEN1.dkim.amazonses.com
    CNAME  TOKEN2._domainkey     → TOKEN2.dkim.amazonses.com
    CNAME  TOKEN3._domainkey     → TOKEN3.dkim.amazonses.com
    ============================================================
  EOT
}

# ── Next steps ────────────────────────────────────────────────
output "next_steps" {
  description = "What to do after terraform apply"
  value       = <<-EOT
    ============================================================
    TERRAFORM COMPLETE — NEXT STEPS
    ============================================================
    1. SSH into your EC2 instance:
       ssh -i ~/.ssh/mastodon_key ubuntu@${module.aws_ec2.public_ip}

    2. Run the bootstrap script:
       scripts/01-bootstrap-server.sh

    3. Add Cloudflare DNS records (see cloudflare_dns_records output)

    4. Run deployment script:
       scripts/02-deploy-mastodon.sh

    5. Create admin account:
       scripts/03-create-admin.sh
    ============================================================
  EOT
}
