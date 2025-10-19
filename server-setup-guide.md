# 服务器安全配置优化指南

本指南适用于 Debian 系列系统，提供完整的服务器安全配置和性能优化方案。

## 目录
- [系统基础设置](#系统基础设置)
- [网络优化 (BBR)](#网络优化-bbr)
- [内存管理 (SWAP)](#内存管理-swap)
- [容器环境 (Docker)](#容器环境-docker)
- [安全加固](#安全加固)
  - [SSH 端口修改](#ssh-端口修改)
  - [密钥认证](#密钥认证)
  - [入侵防护 (fail2ban)](#入侵防护-fail2ban)

---

## 系统基础设置

### 1. 更新系统
```bash
# 更新软件包列表和系统
apt update -y && apt upgrade -y

# 安装必备工具
apt install sudo curl wget nano -y
```

### 2. 时区配置
```bash
# 设置时区为上海
sudo timedatectl set-timezone Asia/Shanghai

# 验证时区设置
timedatectl

# 查看所有可用时区
timedatectl list-timezones
```

### 3. 系统性能调优
通过调整内核参数和系统配置来优化服务器性能：

- **内核参数调整**：增加 TCP 缓冲区大小、修改系统队列长度
- **性能优化工具**：自动调整和优化服务器运行状态
- **资源限制设置**：防止资源耗尽攻击

```bash
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Tune/main/tune.sh) -t
```

---

## 网络优化 (BBR)

### BBR 简介
BBR (Bottleneck Bandwidth and RTT) 是 Google 开发的新型拥塞控制算法，具有以下优势：

- ✅ 显著提高网络吞吐量和降低延迟
- ✅ 适应高延迟、高带宽网络环境
- ✅ 优化拥塞控制机制，避免传统算法的不足
- ✅ 提升网络稳定性和可靠性

### 安装 BBRx (推荐)
BBRx 是魔改版本，在启动、排空、带宽探测等阶段进行了参数优化：

```bash
# 安装 BBRx
bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Tune/main/tune.sh) -x

# 重启系统使配置生效
sudo reboot
```

### 验证安装
```bash
# 检查 BBR 模块
lsmod | grep bbr

# 预期输出（首次重启后）
tcp_bbrx
tcp_bbr

# 如果只有 tcp_bbr，等待几分钟后再次重启
sudo reboot

# 再次检查，预期输出
tcp_bbrx
```

### 备选方案
```bash
# 使用秋水逸冰脚本安装原版 BBR
wget --no-check-certificate https://github.com/teddysun/across/raw/master/bbr.sh
chmod +x bbr.sh
./bbr.sh
```

---

## 内存管理 (SWAP)

### SWAP 的作用
SWAP 交换空间在物理内存不足时提供扩展内存，特别适合小内存 VPS：

- 避免内存不足导致的系统性能下降
- 防止进程被强制终止
- 提高系统运行稳定性

### 配置 SWAP
```bash
# 使用脚本自动配置
wget -O swap.sh https://raw.githubusercontent.com/yuju520/Script/main/swap.sh
chmod +x swap.sh
./swap.sh

# 查看内存使用情况
free -m
```

---

## 开发环境配置

### Zsh 和 Oh-My-Zsh

#### Zsh 简介
Zsh (Z Shell) 是一个功能强大的命令行 Shell，具有以下优势：

- ✅ 强大的自动补全功能
- ✅ 丰富的插件生态系统
- ✅ 美观的主题支持
- ✅ 更好的命令历史管理
- ✅ 改进的脚本语法

#### 安装 Zsh 和 Oh-My-Zsh

```bash
# 安装 Zsh 和 Git
apt install zsh git -y

# 安装 Oh-My-Zsh（自动化安装）
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# 设置为默认 Shell
chsh -s $(which zsh)

# 重新登录后生效
```

#### 验证安装

```bash
# 查看 Zsh 版本
zsh --version

# 查看当前 Shell
echo $SHELL

# 查看 Oh-My-Zsh 配置
cat ~/.zshrc
```

#### 常用配置

```bash
# 编辑配置文件
nano ~/.zshrc

# 修改主题（推荐主题）
ZSH_THEME="robbyrussell"  # 默认主题
ZSH_THEME="agnoster"      # 美观主题
ZSH_THEME="powerlevel10k/powerlevel10k"  # 强大主题

# 启用插件
plugins=(git docker node npm)

# 应用配置
source ~/.zshrc
```

### Node.js LTS 安装

#### Node.js 简介
Node.js 是基于 Chrome V8 引擎的 JavaScript 运行时，适用于：

- ✅ 服务端应用开发
- ✅ 前端工具链（Webpack、Vite 等）
- ✅ 命令行工具开发
- ✅ 全栈 JavaScript 开发

#### Debian/Ubuntu 系统

```bash
# 配置 NodeSource 官方仓库（LTS 版本）
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -

# 安装 Node.js
sudo apt-get install -y nodejs

# 验证安装
node --version
npm --version
```

#### CentOS/RHEL/Fedora 系统

```bash
# 配置 NodeSource 官方仓库（LTS 版本）
curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash -

# 安装 Node.js
yum install -y nodejs  # CentOS 7
dnf install -y nodejs  # CentOS 8+/Fedora

# 验证安装
node --version
npm --version
```

#### Arch Linux 系统

```bash
# 安装 Node.js（官方仓库）
pacman -S nodejs npm

# 验证安装
node --version
npm --version
```

#### 配置 npm 镜像（可选）

```bash
# 使用淘宝镜像加速（国内推荐）
npm config set registry https://registry.npmmirror.com

# 验证镜像配置
npm config get registry

# 恢复官方镜像
npm config set registry https://registry.npmjs.org
```

---

## 容器环境 (Docker)

### Docker 安装

#### 海外服务器
```bash
# 方式一
wget -qO- get.docker.com | bash

# 方式二
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
```

#### 国内服务器
```bash
curl https://install.1panel.live/docker-install -o docker-install
sudo bash ./docker-install
rm -f ./docker-install
```

### Docker 管理
```bash
# 查看版本
docker -v

# 设置开机自启
sudo systemctl enable docker

# 验证 Docker Compose（Docker 18.06+ 自带）
docker compose version
```

### 卸载 Docker
```bash
sudo apt-get purge docker-ce docker-ce-cli containerd.io
sudo apt-get remove docker docker-engine
sudo rm -rf /var/lib/docker /var/lib/containerd
```

---

## 安全加固

### SSH 端口修改

修改默认 SSH 端口的安全优势：
- 🛡️ 减少自动化攻击和暴力破解风险
- 🛡️ 降低被扫描工具发现的概率
- 🛡️ 减少无意义的连接请求

```bash
# 修改 SSH 端口为 55520
sudo sed -i 's/^#\?Port 22.*/Port 55520/g' /etc/ssh/sshd_config

# 重启 SSH 服务
sudo systemctl restart sshd
```

> ⚠️ **重要提醒**：修改端口后，请确保防火墙允许新端口访问，并使用新端口连接。

### 密钥认证

使用 SSH 密钥认证替代密码认证，提供更高的安全性：

```bash
# 一键生成密钥配置
wget -O key.sh https://raw.githubusercontent.com/yuju520/Script/main/key.sh
chmod +x key.sh
./key.sh
```

> ⚠️ **重要提醒**：请妥善保存生成的私钥，丢失将无法连接服务器。

### 入侵防护 (fail2ban)

fail2ban 通过监控日志文件自动封锁恶意 IP，提供实时防护。

#### 安装
```bash
apt install fail2ban -y
```

#### 配置
创建本地配置文件（不修改原始配置）：

```bash
nano /etc/fail2ban/jail.local
```

配置内容：
```ini
[DEFAULT]
# IP 白名单
ignoreip = 127.0.0.1

# 允许 IPv6
allowipv6 = auto

# 日志监控后端
backend = systemd

[sshd]
# 启用 SSH 防护
enabled = true

# 过滤规则
filter = sshd
port = ssh

# 防护动作
action = iptables[name=SSH, port=ssh, protocol=tcp]

# 日志文件路径
logpath = /var/log/secure

# 封锁时间（秒）
bantime = 86400

# 检测时间窗口（秒）
findtime = 86400

# 最大失败尝试次数
maxretry = 3
```

#### 启动服务
```bash
# 设置开机自启
sudo systemctl enable fail2ban

# 启动服务
sudo systemctl restart fail2ban

# 查看状态
sudo systemctl status fail2ban

# 查看所有监控项目
fail2ban-client status
```

---

## 总结

完成以上配置后，您的服务器将具备：

✅ **性能优化**：系统调优 + BBR 网络加速 + SWAP 内存管理
✅ **开发环境**：Zsh + Oh-My-Zsh 提升命令行体验
✅ **运行时环境**：Node.js LTS 支持现代化开发
✅ **容器支持**：Docker 环境ready
✅ **安全加固**：非标准端口 + 密钥认证 + 入侵防护

建议定期更新系统和监控服务状态，确保配置持续有效。

---

*配置过程中如遇问题，请根据具体系统环境调整命令参数。*