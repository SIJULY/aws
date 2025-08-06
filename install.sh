#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
GIT_REPO_URL="https://github.com/SIJULY/aws.git"
INSTALL_DIR="/var/www/aws-instance-web"
SERVICE_NAME="aws-web"
APP_PORT="5001" # Use a TCP Port for easier proxying
# --- End Configuration ---

echo "[INFO] Starting AWS Instance Web deployment..."

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run with sudo or as root. Please use 'sudo bash $0'"
    exit 1
fi

echo "[INFO] Updating system and installing dependencies (git, python)..."
apt-get update -y
apt-get install -y git python3 python3-pip python3-venv curl

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

echo "[INFO] Configuring application password..."
read -p "Please enter a secure password for the web interface: " user_password
if [ -z "$user_password" ]; then
    echo "[ERROR] Password cannot be empty."; exit 1
fi
sed -i "s|PASSWORD = \".*\"|PASSWORD = \"$user_password\"|" "$INSTALL_DIR/app.py"

chown -R www-data:www-data "$INSTALL_DIR"

echo "[INFO] Creating Systemd service file..."
cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Gunicorn instance for AWS Instance Web
After=network.target

[Service]
User=www-data
Group=www-data
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

echo "[INFO] Skipping local Nginx configuration as an external proxy is expected."

echo "----------------------------------------------------------------"
echo "[INFO] Deployment is almost complete!"
echo "[INFO] The application backend is now running on port $APP_PORT."
echo ""
echo "[WARN] FINAL STEP: Please go to your Nginx Proxy Manager (or other proxy tool) and create a new Proxy Host."
echo "   - Domain Names: Your server's IP (e.g., $HOSTNAME) or a domain name"
echo "   - Scheme: http"
echo "   - Forward Hostname / IP: 127.0.0.1"
echo "   - Forward Port: $APP_PORT"
echo ""
echo "[WARN] After setting up the proxy, you MUST add your AWS keys:"
echo "[WARN] nano $INSTALL_DIR/key.txt"
echo "----------------------------------------------------------------"
```