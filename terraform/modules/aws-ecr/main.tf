variable "suffix"           {}
variable "mastodon_version" {}
variable "tags"             { type = map(string) }

resource "aws_ecr_repository" "web" {
  name                 = "mastodon/web"
  image_tag_mutability = "MUTABLE"
  tags                 = var.tags
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "streaming" {
  name                 = "mastodon/streaming"
  image_tag_mutability = "MUTABLE"
  tags                 = var.tags
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "web" {
  repository = aws_ecr_repository.web.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 3 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 3 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "streaming" {
  repository = aws_ecr_repository.streaming.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 3 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 3 }
      action       = { type = "expire" }
    }]
  })
}

output "web_repo_url"       { value = aws_ecr_repository.web.repository_url }
output "streaming_repo_url" { value = aws_ecr_repository.streaming.repository_url }
output "registry_id"        { value = aws_ecr_repository.web.registry_id }
