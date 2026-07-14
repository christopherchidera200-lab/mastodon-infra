variable "suffix"              {}
variable "instance_type"       {}
variable "ssh_key_name"        {}
variable "ssh_public_key_path" {}
variable "security_group_id"   {}
variable "mastodon_domain"     {}
variable "tags"                { type = map(string) }

# ── Import SSH public key ─────────────────────────────────────
resource "aws_key_pair" "mastodon" {
  key_name   = var.ssh_key_name
  public_key = file(var.ssh_public_key_path)
  tags       = var.tags
}

# ── Latest Ubuntu 22.04 LTS AMI (us-east-1, x86_64) ─────────
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── EC2 Instance ─────────────────────────────────────────────
resource "aws_instance" "mastodon" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type   # t3.small — 2 vCPU, 2 GB RAM
  key_name               = aws_key_pair.mastodon.key_name
  vpc_security_group_ids = [var.security_group_id]

  # 30 GB root volume — stores Docker images, PostgreSQL data, Redis data
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  # Cloud-init: installs Docker, sets swap, opens firewall ports
  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {
    mastodon_domain = var.mastodon_domain
  }))

  tags = merge(var.tags, { Name = "mastodon-server-${var.suffix}" })

  lifecycle {
    # Prevent accidental termination of running instance
    prevent_destroy = false
  }
}

# ── Elastic IP — static public IP so DNS never changes ────────
resource "aws_eip" "mastodon" {
  instance = aws_instance.mastodon.id
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "mastodon-eip-${var.suffix}" })
}

output "public_ip"  { value = aws_eip.mastodon.public_ip }
output "public_dns" { value = aws_instance.mastodon.public_dns }
output "instance_id"{ value = aws_instance.mastodon.id }
