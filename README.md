# AWS Instance Web

一个用于管理 AWS EC2 和 Lightsail 实例的网页工具。

## 部署

此应用可通过一键脚本部署在全新的 Ubuntu/Debian 服务器上。

1. SSH 登录到您的新 VPS。
2. 运行以下命令 (请将 URL 替换为您自己的 install.sh 脚本的 Raw 地址):

```bash
wget -O install.sh [https://raw.githubusercontent.com/SIJULY/aws/main/install.sh](https://raw.githubusercontent.com/SIJULY/aws/main/install.sh) && sudo bash install.sh