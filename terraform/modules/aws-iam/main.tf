variable "suffix"         {}
variable "aws_account_id" {}
variable "aws_region"     {}
variable "github_repo"    {}

# ── OIDC provider — GitHub Actions authenticates to AWS ──────
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ── GitHub Actions IAM Role (OIDC — no static keys needed) ───
resource "aws_iam_role" "github_actions" {
  name = "mastodon-github-actions-${var.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions" {
  name = "mastodon-cicd-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3Access"
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = [
          "arn:aws:s3:::mastodon-media-${var.suffix}",
          "arn:aws:s3:::mastodon-media-${var.suffix}/*"
        ]
      },
      {
        Sid      = "ECRAccess"
        Effect   = "Allow"
        Action   = ["ecr:*"]
        Resource = "*"
      },
      {
        Sid      = "EC2Describe"
        Effect   = "Allow"
        Action   = ["ec2:Describe*"]
        Resource = "*"
      },
      {
        Sid      = "CloudFrontAccess"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = "*"
      },
      {
        Sid    = "TFStateAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::mastodon-tfstate-873871686800",
          "arn:aws:s3:::mastodon-tfstate-873871686800/*"
        ]
      },
      {
        Sid      = "TFLockAccess"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:us-east-1:873871686800:table/mastodon-tfstate-lock"
      }
    ]
  })
}

# ── App IAM User — Mastodon on EC2 accesses S3 + SES ─────────
resource "aws_iam_user" "mastodon_app" {
  name = "mastodon-app-${var.suffix}"
  path = "/mastodon/"
  tags = { Purpose = "Mastodon app S3 and SES access" }
}

resource "aws_iam_access_key" "mastodon_app" {
  user = aws_iam_user.mastodon_app.name
}

resource "aws_iam_user_policy" "mastodon_app" {
  name = "mastodon-app-policy"
  user = aws_iam_user.mastodon_app.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3MediaAccess"
        Effect = "Allow"
        Action = ["s3:PutObject","s3:GetObject","s3:DeleteObject","s3:PutObjectAcl"]
        Resource = "arn:aws:s3:::mastodon-media-${var.suffix}/*"
      },
      {
        Sid    = "S3BucketList"
        Effect = "Allow"
        Action = ["s3:ListBucket","s3:GetBucketLocation"]
        Resource = "arn:aws:s3:::mastodon-media-${var.suffix}"
      },
      {
        Sid    = "SESSend"
        Effect = "Allow"
        Action = ["ses:SendEmail","ses:SendRawEmail"]
        Resource = "*"
      },
      {
        Sid      = "ECRPull"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPullRepos"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = [
          "arn:aws:ecr:us-east-1:873871686800:repository/mastodon/web",
          "arn:aws:ecr:us-east-1:873871686800:repository/mastodon/streaming"
        ]
      }
    ]
  })
}

output "github_actions_role_arn" { value = aws_iam_role.github_actions.arn }
output "mastodon_user_arn"       { value = aws_iam_user.mastodon_app.arn }
output "access_key_id"           { value = aws_iam_access_key.mastodon_app.id }
output "secret_access_key" {
  value     = aws_iam_access_key.mastodon_app.secret
  sensitive = true
}
