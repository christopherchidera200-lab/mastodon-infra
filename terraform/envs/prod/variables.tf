variable "aws_region" { type = string }
variable "aws_account_id" { type = string }
variable "ssh_key_name" { type = string }
variable "ssh_public_key_path" { type = string }
variable "instance_type" { type = string }
variable "mastodon_domain" { type = string }
variable "mastodon_email" { type = string }
variable "mastodon_version" { type = string }
variable "github_repo" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}

variable "github_oidc_repo" {
  type        = string
  description = "GitHub OIDC subject prefix with numeric IDs: OWNER@OWNER_ID/REPO@REPO_ID"
  default     = "christopherchidera200-lab@279787614/mastodon-infra@1431588689"
}
