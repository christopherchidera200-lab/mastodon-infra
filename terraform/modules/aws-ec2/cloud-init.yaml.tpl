#cloud-config
# Mastodon EC2 server bootstrap
# Runs automatically on first boot — takes 3-5 minutes
# Installs: Docker, Docker Compose, swap file, UFW firewall

package_update: true
package_upgrade: true

packages:
  - curl
  - wget
  - git
  - unzip
  - htop
  - ufw
  - awscli
  - netcat-openbsd

runcmd:
  # ── Swap file (2 GB) ────────────────────────────────────────
  # Critical for t3.small — prevents OOMKill under load
  - fallocate -l 2G /swapfile
  - chmod 600 /swapfile
  - mkswap /swapfile
  - swapon /swapfile
  - echo '/swapfile none swap sw 0 0' >> /etc/fstab
  - echo 'vm.swappiness=10' >> /etc/sysctl.conf
  - sysctl vm.swappiness=10

  # ── Docker ──────────────────────────────────────────────────
  - curl -fsSL https://get.docker.com | sh
  - usermod -aG docker ubuntu
  - systemctl enable docker
  - systemctl start docker

  # ── Docker Compose v2 ───────────────────────────────────────
  - mkdir -p /usr/local/lib/docker/cli-plugins
  - curl -SL https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
  - chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

  # ── UFW firewall ────────────────────────────────────────────
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw --force enable

  # ── Mastodon app directory ───────────────────────────────────
  - mkdir -p /opt/mastodon
  - chown ubuntu:ubuntu /opt/mastodon

  # ── Record domain for scripts ───────────────────────────────
  - echo "${mastodon_domain}" > /etc/mastodon-domain

  # ── Kernel tuning for Mastodon ──────────────────────────────
  - echo 'net.core.somaxconn=1024' >> /etc/sysctl.conf
  - echo 'net.ipv4.tcp_max_syn_backlog=1024' >> /etc/sysctl.conf
  - sysctl -p

final_message: |
  Mastodon EC2 server ready.
  Domain: ${mastodon_domain}
  Docker: installed
  Swap: 2GB active
  Next: SSH in and run scripts/01-bootstrap-server.sh
