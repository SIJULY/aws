#!/bin/bash
set -e

echo "================================================="
echo " Tinyproxy 密码认证代理 一键安装脚本 (IP无限制版)"
echo "================================================="

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以 root 权限运行。"
    exit 1
fi

echo "[INFO] 正在更新软件包列表并安装 Tinyproxy..."
apt-get update -y
apt-get install -y tinyproxy curl

echo ""
echo "[CONFIG] 请为您的代理服务设置认证信息："
read -p " > 请输入代理用户名 [默认为 user]: " PROXY_USER
PROXY_USER=${PROXY_USER:-user}

read -s -p " > 请为用户 '${PROXY_USER}' 设置一个强密码: " PROXY_PASS
echo ""
if [ -z "$PROXY_PASS" ]; then
    echo "错误：密码不能为空。"
    exit 1
fi

echo "[INFO] 正在配置 Tinyproxy..."
CONFIG_FILE="/etc/tinyproxy/tinyproxy.conf"
mv "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%F-%T)"

cat > "$CONFIG_FILE" << EOF
User tinyproxy
Group tinyproxy
Port 8888
Listen 0.0.0.0
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
PidFile "/run/tinyproxy/tinyproxy.pid"
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
MaxRequestsPerChild 0

安全设置: 只允许本机直连，其他所有IP必须通过密码认证
Allow 127.0.0.1
BasicAuth ${PROXY_USER} ${PROXY_PASS}
EOF

echo "[INFO] 正在重启服务并设置防火墙..."
mkdir -p /var/log/tinyproxy
chown -R tinyproxy:tinyproxy /var/log/tinyproxy
systemctl restart tinyproxy
systemctl enable tinyproxy

if command -v ufw &> /dev/null && ufw status | grep -q 'Status: active'; then
    echo "[INFO] 检测到防火墙(ufw)已启用，正在开放端口 8888..."
    ufw allow 8888/tcp
else
    echo "[WARN] 未检测到活动的 ufw 防火墙。请确保您已在云服务商的安全组中放行了 TCP 端口 8888。"
fi

SERVER_B_IP=$(curl -s http://checkip.amazonaws.com || wget -qO- -t1 http://checkip.amazonaws.com)

echo "================================================="
echo "✅ 密码认证代理服务器安装成功！"
echo "================================================="
echo "请记下以下信息，用于配置您的任何客户端："
echo "代理服务器 IP: ${SERVER_B_IP}"
echo "代理端口: 8888"
echo "代理用户名: ${PROXY_USER}"
echo "代理密码: 【您刚刚设置的密码】"
echo "================================================="
