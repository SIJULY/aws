# AWS Instance Web

一个用于管理 AWS EC2 和 Lightsail 实例的网页工具。

## 部署

此应用可通过一键脚本部署在全新的 Ubuntu/Debian 服务器上。

1.  以 `root` 用户身份 SSH 登录到您的新 VPS。
2.  运行下面这一条命令即可：

wget -O install.sh https://raw.githubusercontent.com/SIJULY/aws/main/install.sh && bash install.sh

3.设置代理（可选）

wget -O install.sh https://raw.githubusercontent.com/SIJULY/aws/main/set_proxy.sh && bash set_proxy.sh

代理端运行代码

wget -O install.sh https://raw.githubusercontent.com/SIJULY/aws/main/install_tinyproxy.sh && bash install_tinyproxy.sh
