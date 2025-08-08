#!/bin/bash

# 如果任何命令失败，立即退出脚本
set -e

# --- 主逻辑 ---
echo "================================================="
echo " Tinyproxy 密码认证代理 一键安装脚本 (IP无限制最终版)"
echo "================================================="

# 1. 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以 root 权限运行。"
    exit 1
fi

# 2. 更新系统并安装 Tinyproxy
echo "[INFO] 正在更新软件包列表并安装 Tinyproxy..."
apt-get update -y
apt-get install -y tinyproxy curl

# 3. 交互式获取配置信息
echo ""
echo "[CONFIG] 请为您的代理服务设置认证信息："

read -p " > 请输入代理用户名 [默认为 user]: " PROXY_USER
# 如果用户直接回车，PROXY_USER为空，则将其设置为默认值'user'
PROXY_USER=${PROXY_USER:-user}

read -s -p " > 请为用户 '${PROXY_USER}' 设置一个强密码: " PROXY_PASS
echo "" # read -s 不会换行，我们手动加一个
if [ -z "$PROXY_PASS" ]; then
    echo "错误：密码不能为空。"
    exit 1
fi

# 4. 备份并创建新的配置文件
echo "[INFO] 正在配置 Tinyproxy..."
CONFIG_FILE="/etc/tinyproxy/tinyproxy.conf"
mv "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%F-%T)" # 备份原始配置文件

# 写入基础配置 (最终版 - 允许所有IP，然后用密码验证)
cat > "$CONFIG_FILE" << EOF
# --- 基础设置 ---
User tinyproxy
Group tinyproxy
Port 8888

# --- 连接设置 ---
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
MaxRequestsPerChild 0

# --- 日志文件 ---
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
PidFile "/run/tinyproxy/tinyproxy.pid"

# --- 安全与认证 ---
# 在所有网络接口上监听 (允许公网访问)
Listen 0.0.0.0

# 允许本机和任何外部IP进行连接尝试
Allow 127.0.0.1
Allow 0.0.0.0/0

# 对所有连接强制要求用户名和密码认证
BasicAuth ${PROXY_USER} ${PROXY_PASS}
EOF

# 5. 重启服务并设置防火墙
echo "[INFO] 正在重启服务并设置防火墙..."
# 确保日志目录存在且权限正确
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

# 6. 显示最终结果
SERVER_B_IP=$(curl -s http://checkip.amazonaws.com || wget -qO- -t1 http://checkip.amazonaws.com)

echo "================================================="
echo "✅ 密码认证代理服务器安装成功！"
echo "================================================="
echo "请记下以下信息，用于配置您的客户端："
echo "代理服务器 IP: ${SERVER_B_IP}"
echo "代理端口: 8888"
echo "代理用户名: ${PROXY_USER}"
echo "代理密码: 【您刚刚设置的密码】"
echo "================================================="
