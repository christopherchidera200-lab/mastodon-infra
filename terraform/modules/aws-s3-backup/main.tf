variable "suffix" {}

variable "retention_days" {
  type    = number
  default = 30
}

resource "aws_s3_bucket" "backup" {
  bucket = "mastodon-backup-${var.suffix}"

  # The only off-server copy of the data lives here. Destroying it must be
  # deliberate: set this to false (and empty the bucket) when you mean it.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

output "bucket_name" { value = aws_s3_bucket.backup.id }
output "bucket_arn" { value = aws_s3_bucket.backup.arn }
