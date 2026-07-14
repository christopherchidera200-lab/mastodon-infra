variable "suffix" {}
variable "tags"   { type = map(string) }

resource "aws_security_group" "mastodon" {
  name        = "mastodon-sg-${var.suffix}"
  description = "Mastodon EC2 security group"
  tags        = var.tags

  # SSH — restrict to your IP in production
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # HTTP — Let's Encrypt ACME challenge
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  # HTTPS — Mastodon web + streaming
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  # All outbound — federation, S3, SES, Tor
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }
}

output "security_group_id" { value = aws_security_group.mastodon.id }
