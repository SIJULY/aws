#!/bin/bash

# 如果任何命令失败，立即退出脚本
set -e

# --- 主逻辑 ---
echo "================================================="
echo " Tinyproxy 一键安装脚本"
echo "================================================="

# 1. 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以 root 权限运行。请使用 'sudo bash install_tinyproxy.sh'"
    exit 1
fi

# 2. 更新系统并安装 Tinyproxy
echo "[INFO] 正在更新软件包列表并安装 Tinyproxy..."
apt-get update -y
apt-get install -y tinyproxy curl

# 3. 交互式获取配置信息
echo ""
echo "[CONFIG] 请输入配置信息："

read -p " > 允许连接此代理的客户端IP (您的服务器 IP): " ALLOWED_IP
if [ -z "$ALLOWED_IP" ]; then
    echo "错误：必须输入一个允许访问的IP地址。"
    exit 1
fi

read -p " > 代理要监听的端口 [默认为 8888]: " PROXY_PORT
PROXY_PORT=${PROXY_PORT:-8888} # 如果用户直接回车，则使用默认值 8888

read -p " > 设置代理用户名 (建议设置，留空则不使用密码验证): " PROXY_USER
if [ -n "$PROXY_USER" ]; then
    read -s -p " > 请输入代理密码: " PROXY_PASS
    echo "" # read -s 不会换行，我们手动加一个
    if [ -z "$PROXY_PASS" ]; then
        echo "错误：输入了用户名但密码为空。"
        exit 1
    fi
fi

# 4. 备份并创建新的配置文件
echo "[INFO] 正在配置 Tinyproxy..."
CONFIG_FILE="/etc/tinyproxy/tinyproxy.conf"
mv "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%F-%T)" # 备份原始配置文件

# 写入基础配置
cat > "$CONFIG_FILE" << EOF
User tinyproxy
Group tinyproxy
Port ${PROXY_PORT}
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
Allow 127.0.0.1
Allow ${ALLOWED_IP}
EOF

# 如果设置了用户名和密码，则追加到配置文件
if [ -n "$PROXY_USER" ]; then
    echo "" >> "$CONFIG_FILE"
    echo "# Basic authentication settings" >> "$CONFIG_FILE"
    echo "BasicAuth ${PROXY_USER} ${PROXY_PASS}" >> "$CONFIG_FILE"
fi

# 5. 重启服务并设置防火墙
echo "[INFO] 正在重启服务并设置防火墙..."
systemctl restart tinyproxy
systemctl enable tinyproxy

if command -v ufw &> /dev/null && ufw status | grep -q 'Status: active'; then
    echo "[INFO] 检测到防火墙(ufw)已启用，正在开放端口 ${PROXY_PORT}..."
    ufw allow ${PROXY_PORT}/tcp
else
    echo "[WARN] 未检测到活动的 ufw 防火墙。请确保您已在云服务商的安全组中放行了 TCP 端口 ${PROXY_PORT}。"
fi

# 6. 显示最终结果
SERVER_B_IP=$(curl -s http://checkip.amazonaws.com || wget -qO- -t1 http://checkip.amazonaws.com)

echo "================================================="
echo "✅ Tinyproxy 代理服务器安装成功！"
echo "================================================="
echo "您的代理服务器信息如下："
echo "IP 地址: ${SERVER_B_IP}"
echo "端口: ${PROXY_PORT}"

if [ -n "$PROXY_USER" ]; then
    echo "用户名: ${PROXY_USER}"
    echo "密码: 【已隐藏】"
    echo ""
    echo "请记下并使用下面这个完整的代理 URL:"
    echo "http://${PROXY_USER}:${PROXY_PASS}@${SERVER_B_IP}:${PROXY_PORT}"
else
    echo "（未设置用户名和密码）"
    echo ""
    echo "请记下并使用下面这个完整的代理 URL:"
    echo "http://${SERVER_B_IP}:${PROXY_PORT}"
fi
echo "================================================="
