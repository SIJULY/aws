#!/bin/bash
set -e
echo "================================================="
echo " Tinyproxy 密码认证代理 一键安装脚本"
echo " (IP无限制, 端口: 8888, 用户名: user)"
echo "================================================="
if [ "$(id -u)" -ne 0 ]; then echo "错误：此脚本需要以 root 权限运行。"; exit 1; fi
echo "[INFO] 正在更新软件包列表并安装 Tinyproxy..."
apt-get update -y > /dev/null
apt-get install -y tinyproxy curl > /dev/null
echo ""
echo "[CONFIG] 请为代理服务设置密码："
read -s -p " > 请为默认用户 'user' 设置代理密码: " PROXY_PASS
echo ""
if [ -z "$PROXY_PASS" ]; then echo "错误：密码不能为空。"; exit 1; fi
echo "[INFO] 正在配置 Tinyproxy..."
CONFIG_FILE="/etc/tinyproxy/tinyproxy.conf"
mv "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%F-%T)"
cat > "$CONFIG_FILE" << EOF
User tinyproxy
Group tinyproxy
Port 8888
Timeout 600
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
PidFile "/run/tinyproxy/tinyproxy.pid"
MaxClients 100
Allow 127.0.0.1
BasicAuth user ${PROXY\_PASS}
EOF
echo "[INFO] 正在重启服务并设置防火墙..."
systemctl restart tinyproxy
systemctl enable tinyproxy
if command -v ufw &\> /dev/null && ufw status | grep -q 'Status: active'; then
ufw allow 8888/tcp \> /dev/null
fi
SERVER\_IP=$(curl -s http://checkip.amazonaws.com || wget -qO- -t1 http://checkip.amazonaws.com)
echo "================================================="
echo "✅ 密码认证代理服务器安装成功！"
echo "================================================="
echo "请记下以下信息，用于配置您的客户端："
echo "代理服务器 IP: ${SERVER_IP}"
echo "代理端口: 8888"
echo "代理用户名: user"
echo "代理密码: 【您刚刚设置的密码】"
echo "================================================="
