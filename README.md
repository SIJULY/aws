# 东半球最好用的免费 AWS Instance Web 工具套件

这是一个功能强大的工具套件，源于一个本地 Tkinter 脚本，最终演变为一个包含主应用、代理服务器和一键部署脚本的完整 Web 应用。

## 功能

- **主应用**：提供带密码保护的 Web 界面，用于管理 AWS EC2 和 Lightsail 实例，包括创建、查询、启停、删除、配额查询、区域激活等。
- **代理服务**：可选择性地部署一个独立的代理服务器，为主应用的 AWS 请求提供固定的出口 IP。

---

## 快速使用指南

整个套件包含三个核心脚本，请根据您的需求，按照顺序使用。

### 步骤一：部署主应用 (服务器 A)

此脚本用于在一台**全新的、纯净的 Ubuntu/Debian 服务器**上部署主应用。这是**必需**的第一步。

1.  以 `root` 用户身份 SSH 登录到您的新服务器 A。
2.  运行下面这一条命令即可完成部署：

`wget -O install.sh https://raw.githubusercontent.com/SIJULY/aws/main/install.sh && bash install.sh`

### 步骤二 (可选)：部署代理服务器 (服务器 B)

如果您需要让主应用的 AWS 请求通过一个指定的 IP 地址发出，可以执行此步骤。

准备一台全新的、纯净的 Ubuntu/Debian 服务器 B。

以 `root` 用户身份 SSH 登录到服务器 B。

运行下面这一条命令来安装 Tinyproxy 代理服务：

`wget -O install_tinyproxy.sh https://raw.githubusercontent.com/SIJULY/aws/main/install_tinyproxy.sh && bash install_tinyproxy.sh`

脚本会交互式地提示您为代理服务设置一个密码（用户名默认为user）。安装成功后，请记下 B 服务器的 IP 地址和您设置的密码。

### 步骤三 (可选)：为主应用配置代理 (在服务器 A)

当您成功部署了代理服务器 B 之后，请回到主应用服务器 A，运行以下命令来配置主应用使用 B 服务器的代理。

以 `root` 用户身份 SSH 登录到您的主应用服务器 A。

运行以下一键命令：

`wget -O set_proxy.sh https://raw.githubusercontent.com/SIJULY/aws/main/set_proxy.sh && bash set_proxy.sh`

脚本会提示您输入 B 服务器的 IP 和您在 B 服务器上设置的密码。输入完成后，您的主应用就会通过代理访问 AWS。如果想清除代理，再次运行此脚本并在提示时留空即可。

#### (附) 如何为整台服务器设置全局代理

如果您想让一台服务器（例如服务器 C，或您原来的 A 服务器）的所有网络流量都通过代理服务器 B，请在这台客户端服务器上运行以下命令。

`wget -O set_system_proxy.sh https://raw.githubusercontent.com/SIJULY/aws/main/set_system_proxy.sh && bash set_system_proxy.sh`

脚本会提示您输入 B 服务器的 IP 和密码。成功后，需要重新登录 SSH 才能使全局代理生效。
