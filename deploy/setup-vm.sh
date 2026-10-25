#!/usr/bin/env bash
# One-shot installer for an Ubuntu 22.04 / 24.04 VM (tested on Azure B2ats_v2;
# also fits Oracle Always Free). Run from the project directory as the normal
# login user (azureuser / ubuntu). It installs MySQL 8 and Node 22, loads the database with
# setup.sh, runs the web server as a systemd service on port 3000, and puts
# nginx in front on port 80.
#
#   bash deploy/setup-vm.sh
#
# Re-running is safe; every step is idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"
RUN_USER="$(id -un)"

echo "==> Packages"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server nginx curl ca-certificates

if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | cut -d. -f1)" != "v22" ]]; then
  echo "==> Node 22"
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

echo "==> Swap, so a 1 GB VM cannot freeze the whole machine"
if [[ ! -f /swapfile ]]; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
fi
sudo swapon /swapfile || true
grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null

echo "==> MySQL: event scheduler on, local connections only, small memory footprint"
sudo tee /etc/mysql/mysql.conf.d/smartqueue.cnf >/dev/null <<'EOF'
[mysqld]
event_scheduler          = ON
bind-address             = 127.0.0.1
innodb_buffer_pool_size  = 64M
performance_schema       = OFF
max_connections          = 40
table_open_cache         = 200
tmp_table_size           = 16M
max_heap_table_size      = 16M
EOF
sudo systemctl enable --now mysql
sudo systemctl restart mysql

echo "==> Load the SmartQueue database"
# Ubuntu's MySQL root uses auth_socket, so root works through sudo without a password.
sudo MYSQL_USER=root ./setup.sh

echo "==> Web server dependencies"
(cd server && npm install --omit=dev)

if [[ ! -f server/.env ]]; then
  echo "==> server/.env"
  cat > server/.env <<EOF
PORT=3000
SESSION_SECRET=$(openssl rand -hex 32)
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=SmartQueue
RECEPTIONIST_PASSWORD=Reception@123
NURSE_PASSWORD=Nurse@123
DOCTOR_PASSWORD=Doctor@123
ADMIN_PASSWORD=Admin@123
AUDITOR_PASSWORD=Auditor@123
EOF
fi

echo "==> systemd service"
sudo tee /etc/systemd/system/smartqueue.service >/dev/null <<EOF
[Unit]
Description=SmartQueue web server
After=network.target mysql.service
Requires=mysql.service

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${PROJECT_DIR}/server
ExecStart=$(command -v node) src/server.js
Restart=always
RestartSec=3
Environment=NODE_ENV=production
MemoryMax=250M
OOMScoreAdjust=200

[Install]
WantedBy=multi-user.target
EOF
sudo mkdir -p /etc/systemd/system/mysql.service.d /etc/systemd/system/ssh.service.d
sudo tee /etc/systemd/system/mysql.service.d/memory.conf >/dev/null <<'EOF'
[Service]
MemoryMax=450M
OOMScoreAdjust=300
EOF
sudo tee /etc/systemd/system/ssh.service.d/oom.conf >/dev/null <<'EOF'
[Service]
OOMScoreAdjust=-900
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now smartqueue
sudo systemctl restart mysql
sudo systemctl restart smartqueue

echo "==> nginx on port 80 -> 3000"
sudo tee /etc/nginx/sites-available/smartqueue >/dev/null <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
sudo ln -sf /etc/nginx/sites-available/smartqueue /etc/nginx/sites-enabled/smartqueue
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx

echo "==> Open port 80 in the VM firewall (Oracle images ship with iptables rules; Azure images have none)"
if ! sudo iptables -C INPUT -p tcp --dport 80 -m state --state NEW -j ACCEPT 2>/dev/null; then
  sudo iptables -I INPUT -p tcp --dport 80 -m state --state NEW -j ACCEPT
fi
if command -v netfilter-persistent >/dev/null 2>&1; then
  sudo netfilter-persistent save
fi

IP="$(curl -fsS ifconfig.me || hostname -I | awk '{print $1}')"
echo
echo "Done. SmartQueue is running."
echo "  Site:     http://${IP}/"
echo "  Logs:     sudo journalctl -u smartqueue -f"
echo "  Restart:  sudo systemctl restart smartqueue"
echo "  Reload DB: sudo MYSQL_USER=root ./setup.sh && sudo systemctl restart smartqueue"
echo
echo "If the page does not load, also allow TCP port 80 at the cloud level:"
echo "  Oracle: Networking > VCN > Security Lists > Ingress"
echo "  Azure:  az vm open-port -g <group> -n <vm> --port 80"
