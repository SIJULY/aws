#!/bin/bash
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以 root 权限运行。"
    exit 1
fi

echo "================================================="
echo " 系统级全局代理配置脚本"
echo "================================================="
echo "此脚本将为整台服务器设置或清除 HTTP/HTTPS 代理。"
echo "请输入从代理服务器获取的完整代理 URL (例如: http://user:pass@1.2.3.4:8888)"
read -p "留空并按回车则为'清除代理' -> " PROXY_URL

CONFIG_FILE="/etc/environment"

echo "正在更新系统环境配置..."

# 先删除所有旧的代理设置
sed -i '/HTTP_PROXY/d' "$CONFIG_FILE"
sed -i '/HTTPS_PROXY/d' "$CONFIG_FILE"
sed -i '/http_proxy/d' "$CONFIG_FILE"
sed -i '/https_proxy/d' "$CONFIG_FILE"

# 如果输入了新的代理 URL，则追加新的配置
if [ -n "$PROXY_URL" ]; then
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