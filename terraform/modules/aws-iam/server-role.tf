# ── Server role: lets the EC2 instance upload backups, and nothing else ──
variable "backup_bucket_arn" {
  type        = string
  description = "ARN of the backup bucket the server may upload to"
}

resource "aws_iam_role" "server" {
  name = "mastodon-server-${var.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "server_backup_upload" {
  name = "backup-upload-only"
  role = aws_iam_role.server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "UploadBackups"
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${var.backup_bucket_arn}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "server" {
  name = "mastodon-server-${var.suffix}"
  role = aws_iam_role.server.name
}

output "server_instance_profile_name" { value = aws_iam_instance_profile.server.name }
