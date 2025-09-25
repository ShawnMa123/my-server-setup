#!/bin/bash

# 服务器安全配置优化脚本
# 支持多种 Linux 发行版 (Debian/Ubuntu/CentOS/RHEL/Fedora/Arch/openSUSE)
# 作者：根据 setup.txt 优化而来

set -e  # 遇到错误时退出

# 全局变量
DISTRO=""
PACKAGE_MANAGER=""
SERVICE_MANAGER=""
INSTALL_CMD=""
UPDATE_CMD=""
SSH_CONFIG_PATH="/etc/ssh/sshd_config"
LOG_PATH="/var/log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 用户确认函数
confirm() {
    local message="$1"
    local default="${2:-n}"
    local prompt

    if [ "$default" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    echo -e "${YELLOW}$message $prompt${NC}"
    read -r response

    if [ -z "$response" ]; then
        response="$default"
    fi

    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户或 sudo 权限运行此脚本"
        exit 1
    fi
}

# 检测 Linux 发行版
detect_distro() {
    log_info "正在检测系统发行版..."

    # 检测发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                DISTRO="debian-based"
                PACKAGE_MANAGER="apt"
                INSTALL_CMD="apt install -y"
                UPDATE_CMD="apt update -y && apt upgrade -y"
                LOG_PATH="/var/log/auth.log"
                ;;
            centos|rhel|rocky|almalinux)
                DISTRO="rhel-based"
                if command -v dnf >/dev/null 2>&1; then
                    PACKAGE_MANAGER="dnf"
                    INSTALL_CMD="dnf install -y"
                    UPDATE_CMD="dnf update -y"
                else
                    PACKAGE_MANAGER="yum"
                    INSTALL_CMD="yum install -y"
                    UPDATE_CMD="yum update -y"
                fi
                LOG_PATH="/var/log/secure"
                ;;
            fedora)
                DISTRO="rhel-based"
                PACKAGE_MANAGER="dnf"
                INSTALL_CMD="dnf install -y"
                UPDATE_CMD="dnf update -y"
                LOG_PATH="/var/log/secure"
                ;;
            arch|manjaro)
                DISTRO="arch-based"
                PACKAGE_MANAGER="pacman"
                INSTALL_CMD="pacman -S --noconfirm"
                UPDATE_CMD="pacman -Syu --noconfirm"
                LOG_PATH="/var/log/auth.log"
                ;;
            opensuse*|sles)
                DISTRO="suse-based"
                PACKAGE_MANAGER="zypper"
                INSTALL_CMD="zypper install -y"
                UPDATE_CMD="zypper update -y"
                LOG_PATH="/var/log/messages"
                ;;
            *)
                DISTRO="unknown"
                log_warning "未知的发行版: $ID"
                ;;
        esac
    else
        # 备用检测方法
        if [ -f /etc/debian_version ]; then
            DISTRO="debian-based"
            PACKAGE_MANAGER="apt"
        elif [ -f /etc/redhat-release ]; then
            DISTRO="rhel-based"
            PACKAGE_MANAGER=$(command -v dnf >/dev/null 2>&1 && echo "dnf" || echo "yum")
        elif [ -f /etc/arch-release ]; then
            DISTRO="arch-based"
            PACKAGE_MANAGER="pacman"
        else
            DISTRO="unknown"
        fi
    fi

    # 检测服务管理器
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_MANAGER="systemctl"
    elif command -v service >/dev/null 2>&1; then
        SERVICE_MANAGER="service"
    else
        SERVICE_MANAGER="unknown"
    fi

    log_success "检测到系统: $DISTRO ($PACKAGE_MANAGER)"
    log_info "服务管理器: $SERVICE_MANAGER"
}

# 检查系统兼容性
check_system() {
    detect_distro

    if [ "$DISTRO" = "unknown" ]; then
        log_error "无法识别的 Linux 发行版"
        log_warning "脚本可能无法正常工作"
        if ! confirm "是否继续执行？"; then
            exit 1
        fi
    fi

    # 检查必要的命令
    local missing_commands=()

    for cmd in curl wget; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_warning "缺少必要的命令: ${missing_commands[*]}"
        log_info "将在系统更新时安装这些工具"
    fi
}

# 通用包安装函数
install_package() {
    local packages="$1"
    log_info "正在安装软件包: $packages"

    case "$PACKAGE_MANAGER" in
        apt)
            apt update -y
            $INSTALL_CMD $packages
            ;;
        yum|dnf)
            $INSTALL_CMD $packages
            ;;
        pacman)
            $INSTALL_CMD $packages
            ;;
        zypper)
            $INSTALL_CMD $packages
            ;;
        *)
            log_error "不支持的包管理器: $PACKAGE_MANAGER"
            return 1
            ;;
    esac
}

# 通用服务管理函数
manage_service() {
    local action="$1"
    local service="$2"

    case "$SERVICE_MANAGER" in
        systemctl)
            systemctl "$action" "$service"
            ;;
        service)
            case "$action" in
                enable)
                    chkconfig "$service" on 2>/dev/null || update-rc.d "$service" enable
                    ;;
                start|stop|restart)
                    service "$service" "$action"
                    ;;
                status)
                    service "$service" status
                    ;;
            esac
            ;;
        *)
            log_error "不支持的服务管理器: $SERVICE_MANAGER"
            return 1
            ;;
    esac
}

# 显示欢迎信息
show_welcome() {
    clear
    echo -e "${GREEN}"
    echo "============================================="
    echo "    多发行版服务器安全配置优化脚本"
    echo "============================================="
    echo -e "${NC}"
    echo "支持的 Linux 发行版："
    echo "• Debian/Ubuntu (apt)"
    echo "• CentOS/RHEL/Fedora (yum/dnf)"
    echo "• Arch Linux/Manjaro (pacman)"
    echo "• openSUSE/SLES (zypper)"
    echo ""
    echo "本脚本将帮助您完成以下配置："
    echo "✓ 系统更新和基础工具安装"
    echo "✓ 时区配置"
    echo "✓ 系统性能调优"
    echo "✓ BBR 网络优化"
    echo "✓ SWAP 交换空间配置"
    echo "✓ Docker 环境安装"
    echo "✓ SSH 安全配置"
    echo "✓ fail2ban 入侵防护"
    echo ""

    if ! confirm "是否开始配置？" "y"; then
        log_info "配置已取消"
        exit 0
    fi
}

# 获取发行版特定的基础包列表
get_basic_packages() {
    case "$PACKAGE_MANAGER" in
        apt)
            echo "sudo curl wget nano"
            ;;
        yum|dnf)
            echo "sudo curl wget nano"
            ;;
        pacman)
            echo "sudo curl wget nano"
            ;;
        zypper)
            echo "sudo curl wget nano"
            ;;
        *)
            echo "curl wget nano"
            ;;
    esac
}

# 1. 系统更新和基础工具安装
update_system() {
    echo ""
    echo -e "${BLUE}=== 系统更新和基础工具安装 ===${NC}"

    if confirm "是否更新系统软件包？" "y"; then
        log_info "正在更新软件包列表和系统..."
        case "$PACKAGE_MANAGER" in
            apt)
                apt update -y && apt upgrade -y
                ;;
            yum)
                yum update -y
                ;;
            dnf)
                dnf update -y
                ;;
            pacman)
                pacman -Syu --noconfirm
                ;;
            zypper)
                zypper update -y
                ;;
            *)
                log_warning "未知的包管理器，跳过系统更新"
                return 1
                ;;
        esac
        log_success "系统更新完成"
    fi

    if confirm "是否安装基础工具？" "y"; then
        log_info "正在安装基础工具..."
        local basic_packages
        basic_packages=$(get_basic_packages)
        install_package "$basic_packages"
        log_success "基础工具安装完成"
    fi
}

# 2. 时区配置
configure_timezone() {
    echo ""
    echo -e "${BLUE}=== 时区配置 ===${NC}"

    if confirm "是否配置时区为亚洲/上海？" "y"; then
        log_info "正在设置时区..."
        timedatectl set-timezone Asia/Shanghai
        log_success "时区设置完成"
        log_info "当前时间信息："
        timedatectl
    fi
}

# 3. 系统性能调优
optimize_system() {
    echo ""
    echo -e "${BLUE}=== 系统性能调优 ===${NC}"
    echo "此功能将调整内核参数、TCP 缓冲区大小等来优化服务器性能"

    if confirm "是否执行系统性能调优？" "y"; then
        log_info "正在执行系统调优..."
        if bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Tune/main/tune.sh) -t; then
            log_success "系统调优完成"
        else
            log_error "系统调优失败，请检查网络连接"
        fi
    fi
}

# 4. BBR 网络优化
configure_bbr() {
    echo ""
    echo -e "${BLUE}=== BBR 网络优化 ===${NC}"
    echo "BBR 是 Google 开发的拥塞控制算法，可显著提高网络性能"
    echo "BBRx 是优化版本，相比原版 BBR 效果更好"

    if confirm "是否安装 BBRx 网络优化？" "y"; then
        log_info "正在安装 BBRx..."
        if bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Tune/main/tune.sh) -x; then
            log_success "BBRx 安装完成"
            log_warning "需要重启系统使 BBR 生效，稍后将询问是否重启"
        else
            log_error "BBRx 安装失败"
            if confirm "是否尝试安装备选 BBR 方案？"; then
                log_info "正在下载备选 BBR 脚本..."
                wget --no-check-certificate https://github.com/teddysun/across/raw/master/bbr.sh
                chmod +x bbr.sh
                ./bbr.sh
            fi
        fi
    fi
}

# 5. SWAP 配置
configure_swap() {
    echo ""
    echo -e "${BLUE}=== SWAP 交换空间配置 ===${NC}"
    echo "SWAP 可以在物理内存不足时提供扩展内存，特别适合小内存服务器"

    # 显示当前内存状态
    log_info "当前内存状态："
    free -m

    if confirm "是否配置 SWAP 交换空间？" "y"; then
        log_info "正在配置 SWAP..."
        if wget -O swap.sh https://raw.githubusercontent.com/yuju520/Script/main/swap.sh && chmod +x swap.sh && ./swap.sh; then
            log_success "SWAP 配置完成"
            log_info "配置后内存状态："
            free -m
        else
            log_error "SWAP 配置失败"
        fi
    fi
}

# 6. Docker 安装
install_docker() {
    echo ""
    echo -e "${BLUE}=== Docker 环境安装 ===${NC}"

    if confirm "是否安装 Docker？" "y"; then
        log_info "正在为 $DISTRO 系统安装 Docker..."

        case "$DISTRO" in
            debian-based)
                # Debian/Ubuntu 系统
                if curl -s --connect-timeout 3 www.google.com > /dev/null 2>&1; then
                    log_info "使用官方安装源"
                    if curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh; then
                        log_success "Docker 安装完成"
                    else
                        log_error "官方源安装失败，尝试包管理器安装"
                        install_package "docker.io docker-compose"
                    fi
                else
                    log_info "使用国内镜像源"
                    if curl https://install.1panel.live/docker-install -o docker-install && bash ./docker-install; then
                        log_success "Docker 安装完成"
                    else
                        log_error "镜像源安装失败，尝试包管理器安装"
                        install_package "docker.io docker-compose"
                    fi
                fi
                ;;
            rhel-based)
                # CentOS/RHEL/Fedora 系统
                case "$PACKAGE_MANAGER" in
                    dnf)
                        install_package "docker docker-compose"
                        ;;
                    yum)
                        # 先安装 EPEL 仓库
                        yum install -y epel-release
                        install_package "docker docker-compose"
                        ;;
                esac
                ;;
            arch-based)
                # Arch Linux 系统
                install_package "docker docker-compose"
                ;;
            suse-based)
                # openSUSE 系统
                install_package "docker docker-compose"
                ;;
            *)
                log_warning "未知发行版，尝试通用安装方法"
                if curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh; then
                    log_success "Docker 安装完成"
                else
                    log_error "Docker 安装失败"
                    return 1
                fi
                ;;
        esac

        # 设置开机自启
        manage_service enable docker
        manage_service start docker
        log_success "Docker 已设置为开机自启并启动"

        # 验证安装
        if command -v docker >/dev/null 2>&1; then
            log_info "Docker 版本信息："
            docker --version

            # 检查 Docker Compose
            if docker compose version >/dev/null 2>&1; then
                log_info "Docker Compose 版本信息："
                docker compose version
            elif command -v docker-compose >/dev/null 2>&1; then
                log_info "Docker Compose 版本信息："
                docker-compose --version
            else
                log_warning "Docker Compose 未安装，某些功能可能受限"
            fi
        else
            log_error "Docker 安装验证失败"
        fi
    fi
}

# 7. SSH 端口修改
configure_ssh_port() {
    echo ""
    echo -e "${BLUE}=== SSH 端口修改 ===${NC}"
    echo "修改 SSH 默认端口可以减少自动化攻击和暴力破解风险"

    if confirm "是否修改 SSH 端口？" "n"; then
        echo "请输入新的 SSH 端口（建议使用 1024-65535 范围内的端口）："
        echo "默认建议：55520"
        read -r new_port

        if [ -z "$new_port" ]; then
            new_port=55520
        fi

        # 验证端口号
        if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1024 ] || [ "$new_port" -gt 65535 ]; then
            log_error "无效的端口号，跳过 SSH 端口修改"
            return 1
        fi

        log_warning "即将修改 SSH 端口为 $new_port"
        log_warning "请确保防火墙允许此端口访问，否则可能无法连接服务器"

        if confirm "确认修改吗？" "n"; then
            log_info "正在修改 SSH 端口..."
            sed -i "s/^#\?Port 22.*/Port $new_port/g" /etc/ssh/sshd_config

            if systemctl restart sshd; then
                log_success "SSH 端口已修改为 $new_port"
                log_warning "下次连接请使用端口 $new_port"
            else
                log_error "SSH 服务重启失败"
            fi
        fi
    fi
}

# 8. SSH 密钥认证
configure_ssh_key() {
    echo ""
    echo -e "${BLUE}=== SSH 密钥认证配置 ===${NC}"
    echo "使用密钥认证可以提供比密码认证更高的安全性"

    if confirm "是否配置 SSH 密钥认证？" "n"; then
        log_warning "此操作将生成 SSH 密钥并配置密钥认证"
        log_warning "请务必保存好生成的私钥，丢失将无法连接服务器"

        if confirm "确认继续吗？" "n"; then
            log_info "正在配置 SSH 密钥认证..."
            if wget -O key.sh https://raw.githubusercontent.com/yuju520/Script/main/key.sh && chmod +x key.sh && ./key.sh; then
                log_success "SSH 密钥认证配置完成"
            else
                log_error "SSH 密钥认证配置失败"
            fi
        fi
    fi
}

# 9. fail2ban 安装配置
configure_fail2ban() {
    echo ""
    echo -e "${BLUE}=== fail2ban 入侵防护配置 ===${NC}"
    echo "fail2ban 可以自动监控日志并封锁恶意 IP 地址"

    if confirm "是否安装和配置 fail2ban？" "y"; then
        log_info "正在安装 fail2ban..."
        install_package "fail2ban"

        # 获取发行版特定的 iptables 包名
        local iptables_package=""
        case "$DISTRO" in
            debian-based)
                iptables_package="iptables"
                ;;
            rhel-based)
                iptables_package="iptables-services"
                ;;
            arch-based)
                iptables_package="iptables"
                ;;
            suse-based)
                iptables_package="iptables"
                ;;
        esac

        if [ -n "$iptables_package" ]; then
            log_info "安装 iptables..."
            install_package "$iptables_package" || log_warning "iptables 安装失败，fail2ban 可能无法正常工作"
        fi

        log_info "正在创建配置文件..."

        # 根据发行版选择正确的日志路径和后端
        local backend="systemd"
        local log_path="$LOG_PATH"

        # 对于较老的系统，可能需要使用 auto 后端
        if ! command -v systemctl >/dev/null 2>&1; then
            backend="auto"
        fi

        cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# IP 白名单
ignoreip = 127.0.0.1/8 ::1

# 允许 IPv6
allowipv6 = auto

# 日志修改检测机制
backend = $backend

# 针对各服务的检查配置

[sshd]
# 启用 SSH 防护
enabled = true

# 过滤规则
filter = sshd
port = ssh

# 防护动作
action = iptables[name=SSH, port=ssh, protocol=tcp]

# 日志文件路径
logpath = $log_path

# 封锁时间（秒）
bantime = 86400

# 检测时间窗口（秒）
findtime = 86400

# 最大失败尝试次数
maxretry = 3
EOF

        # 启动服务
        manage_service enable fail2ban
        manage_service start fail2ban

        # 验证服务状态
        sleep 2
        if manage_service status fail2ban >/dev/null 2>&1; then
            log_success "fail2ban 配置完成并已启动"
            log_info "fail2ban 状态："
            if command -v fail2ban-client >/dev/null 2>&1; then
                fail2ban-client status || log_warning "fail2ban-client 状态查询失败"
            fi
        else
            log_error "fail2ban 启动失败，请检查配置"
        fi
    fi
}

# 完成配置
finish_setup() {
    echo ""
    echo -e "${GREEN}=== 配置完成 ===${NC}"
    log_success "多发行版服务器安全配置优化已完成！"

    echo ""
    echo "系统信息摘要："
    echo "• 发行版: $DISTRO"
    echo "• 包管理器: $PACKAGE_MANAGER"
    echo "• 服务管理器: $SERVICE_MANAGER"
    echo ""
    echo "配置摘要："
    echo "✓ 系统已优化"
    echo "✓ 网络性能已提升"
    echo "✓ 安全防护已加强"

    # 检查是否需要重启
    local need_reboot=false

    # 检查不同发行版的重启标记
    if [ -f /var/run/reboot-required ]; then
        need_reboot=true
    elif lsmod | grep -q bbr; then
        need_reboot=true
    elif [ "$DISTRO" = "rhel-based" ] && [ -f /var/run/reboot-required ]; then
        need_reboot=true
    fi

    if [ "$need_reboot" = true ]; then
        echo ""
        log_warning "检测到需要重启系统以使某些配置生效"
        if confirm "是否立即重启系统？" "y"; then
            log_info "系统将在 5 秒后重启..."
            sleep 5
            reboot
        else
            log_warning "请稍后手动重启系统以使配置完全生效"
        fi
    fi

    echo ""
    log_info "感谢使用多发行版服务器配置脚本！"
}

# 主函数
main() {
    # 检查权限和系统
    check_root
    check_system

    # 显示欢迎信息
    show_welcome

    # 执行各项配置
    update_system
    configure_timezone
    optimize_system
    configure_bbr
    configure_swap
    install_docker
    configure_ssh_port
    configure_ssh_key
    configure_fail2ban

    # 完成配置
    finish_setup
}

# 脚本入口
main "$@"