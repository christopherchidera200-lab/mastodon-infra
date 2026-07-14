variable "suffix"          {}
variable "mastodon_domain" {}
variable "iam_user_arn"    {}
variable "tags"            { type = map(string) }

resource "aws_s3_bucket" "media" {
  bucket = "mastodon-media-${var.suffix}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["https://${var.mastodon_domain}"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    id     = "expire-remote-cache"
    status = "Enabled"
    filter { prefix = "cache/" }
    expiration { days = 30 }
  }
}

# CloudFront OAC
resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "mastodon-oac-${var.suffix}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "media" {
  enabled         = true
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"
  comment         = "Mastodon media CDN"
  tags            = var.tags

  origin {
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id                = "mastodon-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }

  ordered_cache_behavior {
    path_pattern           = "/media_attachments/*"
    target_origin_id       = "mastodon-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  default_cache_behavior {
    target_origin_id       = "mastodon-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOAC"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.media.arn}/*"
        Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.media.arn } }
      },
      {
        Sid       = "AllowMastodonApp"
        Effect    = "Allow"
        Principal = { AWS = var.iam_user_arn }
        Action    = ["s3:PutObject","s3:GetObject","s3:DeleteObject","s3:PutObjectAcl"]
        Resource  = "${aws_s3_bucket.media.arn}/*"
      }
    ]
  })
}

output "bucket_name"       { value = aws_s3_bucket.media.id }
output "cloudfront_domain" { value = aws_cloudfront_distribution.media.domain_name }
output "cloudfront_id"     { value = aws_cloudfront_distribution.media.id }
