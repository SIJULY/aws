#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
GIT_REPO_URL="https://github.com/SIJULY/aws.git"
INSTALL_DIR="/var/www/aws-instance-web"
SERVICE_NAME="aws-web"
APP_PORT="5001"
# --- End Configuration ---

echo "[INFO] Starting AWS Instance Web deployment..."

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run with sudo or as root. Please use 'sudo bash $0'"
    exit 1
fi

# --- [修改] 安装 Caddy Web服务器 ---
echo "[INFO] Installing dependencies (git, python, caddy)..."
apt-get update -y
apt-get install -y git python3 python3-pip python3-venv curl
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update -y
apt-get install -y caddy

echo "[INFO] Cloning application from GitHub repository..."
if [ -d "$INSTALL_DIR" ]; then
    echo "[WARN] Backing up existing directory: $INSTALL_DIR"
    mv "$INSTALL_DIR" "$INSTALL_DIR.bak.$(date +%F-%T)"
fi
git clone "$GIT_REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "[INFO] Setting up Python virtual environment..."
python3 -m venv venv
venv/bin/pip install -r requirements.txt

echo "[INFO] Creating empty key file. You must edit it later."
touch "$INSTALL_DIR/key.txt"

# --- [修改] 优化密码提示 ---
echo "[INFO] Configuring application password..."
read -p "请输入网页应用的登录密码: " user_password
if [ -z "$user_password" ]; then
    echo "[ERROR] Password cannot be empty."; exit 1
fi
sed -i "s|PASSWORD = \".*\"|PASSWORD = \"$user_password\"|" "$INSTALL_DIR/app.py"

chown -R caddy:caddy "$INSTALL_DIR" # Caddy 默认使用 caddy 用户

echo "[INFO] Creating Systemd service file..."
cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Gunicorn instance for AWS Instance Web
After=network.target

[Service]
User=caddy
Group=caddy
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:$APP_PORT app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF
echo "[INFO] Starting and enabling application service..."
systemctl daemon-reload
systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
systemctl start "$SERVICE_NAME"
systemctl enable "$SERVICE_NAME"

# --- [修改] 增加域名询问和Caddy配置逻辑 ---
echo "[INFO] Configuring Caddy reverse proxy..."
read -p "请输入您的域名 (如果留空, 将使用IP地址访问): " DOMAIN_NAME

SERVER_IP=$(curl -s http://checkip.amazonaws.com || wget -qO- -t1 http://checkip.amazonaws.com)
ADDRESS_TO_USE=$SERVER_IP
PROTOCOL="http"

if [ -n "$DOMAIN_NAME" ]; then
    echo "[INFO] Domain name provided. Configuring Caddy for $DOMAIN_NAME with automatic HTTPS..."
    ADDRESS_TO_USE=$DOMAIN_NAME
    PROTOCOL="https"
    CADDY_CONFIG="$DOMAIN_NAME {
    reverse_proxy 127.0.0.1:$APP_PORT
}"
else
    echo "[INFO] No domain name provided. Configuring Caddy for IP address access..."
    CADDY_CONFIG="http://$SERVER_IP {
    reverse_proxy 127.0.0.1:$APP_PORT
}"
fi

echo "$CADDY_CONFIG" > /etc/caddy/Caddyfile
systemctl restart caddy

echo "----------------------------------------------------------------"
echo "[INFO] 部署成功！(Deployment Complete!)"
echo "[INFO] 您的应用已准备就绪，请通过以下地址登录："
echo "[INFO] 登录地址 (Login Address): $PROTOCOL://$ADDRESS_TO_USE"
echo ""
echo "[WARN] 【重要】如果您使用了域名，请确保域名的A记录已指向IP: $SERVER_IP"
echo "[WARN] 【重要】登录后，您必须在应用内手动添加您的AWS密钥才能使用！"
echo "[WARN]   1. 使用您在安装时设置的密码登录 Web 界面。"
echo "[WARN]   2. 进入“管理AWS账户”并添加您的密钥。"
echo "----------------------------------------------------------------"