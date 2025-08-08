#!/bin/bash

# 如果任何命令失败，立即退出脚本
set -e

# --- 变量定义 ---
SERVICE_FILE="/etc/systemd/system/aws-web.service"
SERVICE_NAME="aws-web.service"

# --- 主逻辑 ---

# 1. 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以 root 权限运行。请使用 'sudo bash set_proxy.sh' 或以 root 用户身份直接运行 'bash set_proxy.sh'"
    exit 1
fi

# 2. 检查systemd文件是否存在
if [ ! -f "$SERVICE_FILE" ]; then
    echo "错误：找不到服务文件 '$SERVICE_FILE'。请确保主应用已正确安装。"
    exit 1
fi

# 3. 提示用户输入
echo "================================================="
echo " AWS 应用代理设置 (运行于 A 服务器)"
echo "================================================="
echo "请输入从 B 服务器获取的完整代理 URL (例如: http://user:pass@1.2.3.4:8888)"
read -p "留空并按回车则为'清除代理' -> " PROXY_URL

# 4. 修改 systemd 服务文件
echo "正在更新服务配置..."

# 无论如何，先删除所有旧的代理设置，确保一个干净的状态
sed -i '/Environment="HTTP_PROXY=/d' "$SERVICE_FILE"
sed -i '/Environment="HTTPS_PROXY=/d' "$SERVICE_FILE"

# 如果用户输入了新的代理 URL，则添加新的配置
if [ -n "$PROXY_URL" ]; then
    # 我们将新行插入到 "WorkingDirectory=" 这一行的下面
    sed -i "/WorkingDirectory=.*/a Environment=\"HTTPS_PROXY=$PROXY_URL\"" "$SERVICE_FILE"
    sed -i "/WorkingDirectory=.*/a Environment=\"HTTP_PROXY=$PROXY_URL\"" "$SERVICE_FILE"
    echo "成功：代理已设置为 -> $PROXY_URL"
else
    echo "成功：已清除所有代理设置。"
fi

# 5. 重新加载配置并重启服务
echo "正在重新加载配置并重启服务..."
systemctl daemon-reload
systemctl restart "$SERVICE_NAME"

echo "================================================="
echo "操作完成！您的新设置已生效。"
echo "================================================="
