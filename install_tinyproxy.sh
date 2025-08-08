#!/bin/bash

# 如果任何命令失败，立即退出脚本
set -e

# --- 主逻辑 ---
echo "================================================="
echo " Tinyproxy 密码认证代理 一键安装脚本"
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

# 3. 交互式获取配置信息 (已修改)
echo ""
echo "[CONFIG] 请为您的代理服务设置用户名和密码："

read -p " > 请输入代理用户名: " PROXY_USER
if [ -z "$PROXY_USER" ]; then
    echo "错误：用户名不能为空。"
    exit 1
fi

read -s -p " > 请输入代理密码: " PROXY_PASS
echo "" # read -s 不会换行，我们手动加一个
if [ -z "$PROXY_PASS" ]; then
    echo "错误：密码不能为空。"
    exit 1
fi

# 4. 备份并创建新的配置文件 (已修改)
echo "[INFO] 正在配置 Tinyproxy..."
CONFIG_FILE="/etc/tinyproxy/tinyproxy.conf"
mv "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%F-%T)" # 备份原始配置文件

# 写入基础配置 (已移除IP限制，固定端口，并直接加入密码)
cat > "$CONFIG_FILE" << EOF
User tinyproxy
Group tinyproxy
Port 8888
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

# 只允许本机访问，外部访问必须通过密码认证
Allow 127.0.0.1

# 基础认证设置
BasicAuth ${PROXY_USER} ${PROXY_PASS}
EOF

# 5. 重启服务并设置防火墙 (已修改)
echo "[INFO] 正在重启服务并设置防火墙..."
systemctl restart tinyproxy
systemctl enable tinyproxy

if command -v ufw &> /dev/null && ufw status | grep -q 'Status: active'; then
    echo "[INFO] 检测到防火墙(ufw)已启用，正在开放端口 8888..."
    ufw allow 8888/tcp
else
    echo "[WARN] 未检测到活动的 ufw 防火墙。请确保您已在云服务商的安全组中放行了 TCP 端口 8888。"
fi

# 6. 显示最终结果 (已修改)
SERVER_B_IP=$(curl -s http://checkip.amazonaws.com || wget -qO- -t1 http://checkip.amazonaws.com)

echo "================================================="
echo "✅ 密码认证代理服务器安装成功！"
echo "================================================="
echo "您的代理服务器信息如下："
echo "IP 地址: ${SERVER_B_IP}"
echo "端口: 8888"
echo "用户名: ${PROXY_USER}"
echo "密码: 【已隐藏】"
echo ""
echo "请在需要使用代理的地方，填入下面这个完整的代理 URL:"
echo "http://${PROXY_USER}:${PROXY_PASS}@${SERVER_B_IP}:8888"
echo "================================================="
