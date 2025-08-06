#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
GIT_REPO_URL="https://github.com/SIJULY/aws.git"
INSTALL_DIR="/var/www/aws-instance-web"
SERVICE_NAME="aws-web"
# --- End Configuration ---

# --- Main Script ---
echo "[INFO] Starting AWS Instance Web deployment..."

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run with sudo or as root. Please use 'sudo bash $0'"
    exit 1
fi

# 1. Update system and install dependencies
echo "[INFO] Updating system and installing dependencies (git, python, nginx)..."
apt-get update -y
apt-get install -y git python3 python3-pip python3-venv nginx curl

# 2. Clone repository and set up application
echo "[INFO] Cloning application from GitHub repository..."
if [ -d "$INSTALL_DIR" ]; then
    echo "[WARN] Installation directory $INSTALL_DIR already exists. Backing it up."
    mv "$INSTALL_DIR" "$INSTALL_DIR.bak.$(date +%F-%T)"
fi
git clone "$GIT_REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "[INFO] Setting up Python virtual environment and installing packages..."
python3 -m venv venv
venv/bin/pip install -r requirements.txt

echo "[INFO] Creating empty key file. You must edit this file later."
touch "$INSTALL_DIR/key.txt"

# 3. Prompt for password and configure app.py
echo "[INFO] Configuring application..."
read -p "Please enter a secure password for the web interface: " user_password
if [ -z "$user_password" ]; then
    echo "[ERROR] Password cannot be empty."
    exit 1
fi
# Use a different delimiter for sed to avoid issues with passwords containing slashes
sed -i "s|PASSWORD = \".*\"|PASSWORD = \"$user_password\"|" "$INSTALL_DIR/app.py"

# Set permissions
chown -R www-data:www-data "$INSTALL_DIR"

# 4. Set up Systemd service
echo "[INFO] Creating Systemd service file..."
cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF