#!/bin/bash
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以 root 权限运行。"
    exit 1
fi

CONFIG_FILE="/etc/environment"
PROXY_USER="user"
PROXY_PORT="8888"

echo "================================================="
echo " 系统级全局代理配置脚本"
echo "================================================="
echo "此脚本将为整台服务器设置或清除 HTTP/HTTPS 代理。"
echo "（内置代理用户名: user, 端口: 8888）"
echo ""

read -p " > 请输入代理服务器的 IP 地址 (留空则清除代理): " PROXY_IP

# 先清除所有旧的代理设置
echo "正在更新系统环境配置..."
sed -i '/HTTP_PROXY/d' "$CONFIG_FILE"
sed -i '/HTTPS_PROXY/d' "$CONFIG_FILE"
sed -i '/http_proxy/d' "$CONFIG_FILE"
sed -i '/https_proxy/d' "$CONFIG_FILE"

# 如果用户输入了IP，则继续询问密码并设置
if [ -n "$PROXY_IP" ]; then
    read -s -p " > 请输入为代理用户 'user' 设置的密码: " PROXY_PASS
    echo ""
    if [ -z "$PROXY_PASS" ]; then
        echo "错误：密码不能为空。"
        exit 1
    fi

    # 构建完整的代理URL
    PROXY_URL="http://${PROXY_USER}:${PROXY_PASS}@${PROXY_IP}:${PROXY_PORT}"

    # 追加新的配置
    echo "HTTP_PROXY=\"${PROXY_URL}\"" >> "$CONFIG_FILE"
    echo "HTTPS_PROXY=\"${PROXY_URL}\"" >> "$CONFIG_FILE"
    echo "http_proxy=\"${PROXY_URL}\"" >> "$CONFIG_FILE"
    echo "https_proxy=\"${PROXY_URL}\"" >> "$CONFIG_FILE"
    echo "成功：系统代理已设置为 -> $PROXY_URL"
else
    echo "成功：已清除所有系统代理设置。"
fi

echo "================================================="
echo "✅ 操作完成！"
echo "[WARN] 【重要】请退出当前 SSH 连接，然后重新登录，新的代理设置才会对您的操作生效！"
echo "================================================="
