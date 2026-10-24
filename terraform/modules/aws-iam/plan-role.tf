# ── Plan role permissions: read-only, plus the state backend ──
resource "aws_iam_role_policy_attachment" "github_actions_readonly" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "github_actions" {
  name = "mastodon-plan-state-access"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # plan reads state but never writes it back
        Sid    = "TFStateRead"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::mastodon-tfstate-${var.aws_account_id}",
          "arn:aws:s3:::mastodon-tfstate-${var.aws_account_id}/*"
        ]
      },
      {
        # locking is a write to the lock table
        Sid      = "TFLock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/mastodon-tfstate-lock"
      }
    ]
  })
}
