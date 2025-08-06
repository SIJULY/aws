#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# 【重要】请将这里的URL替换为您自己创建的GitHub仓库的URL
GIT_REPO_URL="GIT_REPO_URL="https://github.com/SIJULY/aws.git"
INSTALL_DIR="/var/www/aws-instance-web"
SERVICE_NAME="aws-web"
# --- End Configuration ---

# --- Helper Functions for Colored Output ---
info() { echo -e "\e[32m[INFO]\e[0m $1"; }
warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
error() { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

# --- Main Script ---
main() {
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run with sudo or as root. Please use 'sudo bash $0'"
    fi

    info "Starting AWS Instance Web deployment..."

    # 1. Update system and install dependencies
    info "Updating system and installing dependencies (git, python, nginx)..."
    apt-get update -y
    apt-get install -y git python3 python3-pip python3-venv nginx curl

    # 2. Clone repository and set up application
    info "Cloning application from GitHub repository..."
    if [ -d "$INSTALL_DIR" ]; then
        warn "Installation directory $INSTALL_DIR already exists. Backing up."
        mv "$INSTALL_DIR" "$INSTALL_DIR.bak.$(date +%F-%T)"
    fi
    git clone "$GIT_REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    info "Setting up Python virtual environment and installing packages..."
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    deactivate

    info "Creating empty key file. You must edit this file later."
    touch "$INSTALL_DIR/key.txt"

    # 3. Prompt for password and configure app.py
    info "Configuring application..."
    read -p "Please enter a secure password for the web interface: " user_password
    if [ -z "$user_password" ]; then
        error "Password cannot be empty."
    fi
    # Use a different delimiter for sed to avoid issues with passwords containing slashes
    sed -i "s|PASSWORD = \".*\"|PASSWORD = \"$user_password\"|" "$INSTALL_DIR/app.py"

    # Set permissions
    chown -R www-data:www-data "$INSTALL_DIR"
    find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
    find "$INSTALL_DIR" -type f -exec chmod 644 {} \;

    # 4. Set up Systemd service
    info "Creating Systemd service file..."
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Gunicorn instance to serve AWS Instance Web app
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/gunicorn --workers 3 --bind unix:$SERVICE_NAME.sock -m 007 app:app

[Install]
WantedBy=multi-user.target
EOF

    info "Starting and enabling the application service..."
    systemctl daemon-reload
    systemctl start "$SERVICE_NAME"
    systemctl enable "$SERVICE_NAME"

    # 5. Set up Nginx
    info "Configuring Nginx reverse proxy..."
    SERVER_IP=$(curl -s http://checkip.amazonaws.com || wget -qO- -t1 http://checkip.amazonaws.com)
    rm -f /etc/nginx/sites-enabled/default

    cat > "/etc/nginx/sites-available/$SERVICE_NAME" << EOF
server {
    listen 80;
    server_name $SERVER_IP _;

    location / {
        include proxy_params;
        proxy_pass http://unix:$INSTALL_DIR/$SERVICE_NAME.sock;
    }
}
EOF

    ln -sfn "/etc/nginx/sites-available/$SERVICE_NAME" "/etc/nginx/sites-enabled/$SERVICE_NAME"
    nginx -t
    systemctl restart nginx

    info "Deployment complete!"
    echo "-----------------------------------------------------"
    info "Your AWS Instance Web is now running."
    info "Access it at: http://$SERVER_IP"
    warn "IMPORTANT: The application is running, but you MUST add your AWS keys."
    warn "Please SSH into your server and edit the key file:"
    warn "nano $INSTALL_DIR/key.txt"
    echo "-----------------------------------------------------"
}

main