variable "mastodon_domain" {}
variable "mastodon_email"  {}
variable "suffix"          {}

resource "aws_ses_domain_identity" "mastodon" {
  domain = var.mastodon_domain
}

resource "aws_ses_domain_dkim" "mastodon" {
  domain = aws_ses_domain_identity.mastodon.domain
}

resource "aws_ses_email_identity" "admin" {
  email = var.mastodon_email
}

resource "aws_iam_user" "ses_smtp" {
  name = "mastodon-ses-smtp-${var.suffix}"
  path = "/mastodon/"
}

resource "aws_iam_access_key" "ses_smtp" {
  user = aws_iam_user.ses_smtp.name
}

resource "aws_iam_user_policy" "ses_smtp" {
  name = "ses-smtp-send"
  user = aws_iam_user.ses_smtp.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendRawEmail"]
      Resource = "*"
    }]
  })
}

output "domain_verification_token" { value = aws_ses_domain_identity.mastodon.verification_token }
output "dkim_tokens"               { value = aws_ses_domain_dkim.mastodon.dkim_tokens }
output "smtp_username"             { value = aws_iam_access_key.ses_smtp.id }
output "smtp_password" {
  value     = aws_iam_access_key.ses_smtp.ses_smtp_password_v4
  sensitive = true
}
