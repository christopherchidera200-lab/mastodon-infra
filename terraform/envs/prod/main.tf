terraform {
  required_version = ">= 1.7"

  backend "s3" {
    bucket         = "mastodon-tfstate-873871686800"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "mastodon-tfstate-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  suffix = random_id.suffix.hex
  tags = {
    Project     = "mastodon"
    Environment = "prod"
    ManagedBy   = "terraform"
    Owner       = "christopherchidera200@gmail.com"
  }
}

# ── Security Group ────────────────────────────────────────────
module "aws_sg" {
  source = "../../modules/aws-sg"
  suffix = local.suffix
  tags   = local.tags
}

# ── EC2 Instance ──────────────────────────────────────────────
module "aws_ec2" {
  source              = "../../modules/aws-ec2"
  suffix              = local.suffix
  instance_type       = var.instance_type
  ssh_key_name        = var.ssh_key_name
  ssh_public_key_path = var.ssh_public_key_path
  security_group_id   = module.aws_sg.security_group_id
  mastodon_domain     = var.mastodon_domain
  tags                = local.tags
}

# ── IAM — OIDC for GitHub Actions + app user for S3 ──────────
module "aws_iam" {
  source         = "../../modules/aws-iam"
  suffix         = local.suffix
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region
  github_repo    = var.github_repo
}

# ── S3 + CloudFront ───────────────────────────────────────────
module "aws_s3_cloudfront" {
  source          = "../../modules/aws-s3-cloudfront"
  suffix          = local.suffix
  mastodon_domain = var.mastodon_domain
  iam_user_arn    = module.aws_iam.mastodon_user_arn
  tags            = local.tags
}

# ── SES ───────────────────────────────────────────────────────
module "aws_ses" {
  source          = "../../modules/aws-ses"
  mastodon_domain = var.mastodon_domain
  mastodon_email  = var.mastodon_email
  suffix          = local.suffix
}

# ── ECR ───────────────────────────────────────────────────────
module "aws_ecr" {
  source           = "../../modules/aws-ecr"
  suffix           = local.suffix
  mastodon_version = var.mastodon_version
  tags             = local.tags
}
