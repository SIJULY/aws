#!/bin/bash
set -e

SERVICE_FILE="/etc/systemd/system/aws-web.service"
SERVICE_NAME="aws-web.service"
PROXY_USER="user"
PROXY_PORT="8888"

if [ "$(id -u)" -ne 0 ]; then echo "错误：此脚本需要以 root 权限运行。"; exit 1; fi
if [ ! -f "$SERVICE_FILE" ]; then echo "错误：找不到服务文件 '$SERVICE_FILE'。"; exit 1; fi

echo "================================================="
echo " AWS 应用代理客户端配置脚本"
echo "================================================="
echo "此脚本将配置本机的 AWS 应用去使用一个已存在的代理服务器。"
echo "（内置代理用户名: user, 端口: 8888）"

read -p " > 请输入代理服务器的 IP 地址: " PROXY_IP
if [ -z "$PROXY_IP" ]; then echo "错误：IP 地址不能为空。"; exit 1; fi

read -s -p " > 请输入为代理服务器 'user' 用户设置的密码: " PROXY_PASS
echo ""
if [ -z "$PROXY_PASS" ]; then echo "错误：密码不能为空。"; exit 1; fi

PROXY_URL="http://${PROXY_USER}:${PROXY_PASS}@${PROXY_IP}:${PROXY_PORT}"

echo "正在更新服务配置..."
sed -i '/Environment="HTTP_PROXY=/d' "$SERVICE_FILE"
sed -i '/Environment="HTTPS_PROXY=/d' "$SERVICE_FILE"
sed -i "/WorkingDirectory=.*/a Environment=\"HTTPS_PROXY=$PROXY_URL\"" "$SERVICE_FILE"
sed -i "/WorkingDirectory=.*/a Environment=\"HTTP_PROXY=$PROXY_URL\"" "$SERVICE_FILE"
echo "成功：代理已设置为 -> ${PROXY_URL}"

echo "正在重新加载配置并重启服务..."
systemctl daemon-reload
systemctl restart "$SERVICE_NAME"

echo "================================================="
echo "✅ 操作完成！您的应用现在将通过代理访问 AWS。"
echo "================================================="
