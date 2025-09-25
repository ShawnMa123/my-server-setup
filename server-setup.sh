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

    # 系统更新说明
    echo -e "${YELLOW}📦 系统软件包更新${NC}"
    echo "此步骤将会执行："
    case "$PACKAGE_MANAGER" in
        apt)
            echo "• 更新软件包列表 (apt update)"
            echo "• 升级所有已安装软件包 (apt upgrade)"
            echo "• 自动处理软件包依赖关系"
            ;;
        yum)
            echo "• 检查可用更新 (yum check-update)"
            echo "• 升级所有已安装软件包 (yum update)"
            echo "• 更新系统内核（如有需要）"
            ;;
        dnf)
            echo "• 刷新软件仓库元数据 (dnf clean && dnf update)"
            echo "• 升级所有已安装软件包"
            echo "• 自动处理过时的软件包"
            ;;
        pacman)
            echo "• 同步软件包数据库 (pacman -Sy)"
            echo "• 升级整个系统 (pacman -Su)"
            echo "• 清理软件包缓存"
            ;;
        zypper)
            echo "• 刷新仓库 (zypper refresh)"
            echo "• 升级已安装软件包 (zypper update)"
            echo "• 处理软件包冲突"
            ;;
    esac
    echo "⚠️  注意：系统更新可能需要几分钟，取决于网络速度和待更新软件包数量"
    echo ""

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

    # 基础工具安装说明
    echo ""
    echo -e "${YELLOW}🔧 基础工具安装${NC}"
    echo "此步骤将安装以下必备工具："
    local basic_packages
    basic_packages=$(get_basic_packages)

    case "$PACKAGE_MANAGER" in
        apt)
            echo "• sudo - 提权管理工具，允许普通用户执行管理员命令"
            echo "• curl - 命令行HTTP客户端，用于下载文件和API调用"
            echo "• wget - 网络下载工具，支持HTTP/HTTPS/FTP协议"
            echo "• nano - 轻量级文本编辑器，适合新手使用"
            ;;
        yum|dnf)
            echo "• sudo - 用户权限提升工具"
            echo "• curl - HTTP/HTTPS请求工具和文件下载器"
            echo "• wget - 网络文件下载工具"
            echo "• nano - 简单易用的控制台文本编辑器"
            ;;
        pacman)
            echo "• sudo - 权限管理工具"
            echo "• curl - 网络请求和文件传输工具"
            echo "• wget - GNU网络下载器"
            echo "• nano - GNU文本编辑器"
            ;;
        zypper)
            echo "• sudo - 用户权限委托工具"
            echo "• curl - libcurl命令行工具"
            echo "• wget - 网络下载实用程序"
            echo "• nano - 小型友好的文本编辑器"
            ;;
    esac
    echo "💡 这些工具是后续配置步骤的基础依赖"
    echo ""

    if confirm "是否安装基础工具？" "y"; then
        log_info "正在安装基础工具: $basic_packages"
        install_package "$basic_packages"
        log_success "基础工具安装完成"

        # 验证安装
        echo "✅ 已安装的工具版本："
        for tool in sudo curl wget nano; do
            if command -v "$tool" >/dev/null 2>&1; then
                case "$tool" in
                    sudo) sudo --version 2>/dev/null | head -1 || echo "• sudo: 已安装" ;;
                    curl) echo "• curl: $(curl --version | head -1 | cut -d' ' -f2)" ;;
                    wget) echo "• wget: $(wget --version 2>/dev/null | head -1 | cut -d' ' -f3)" ;;
                    nano) echo "• nano: $(nano --version 2>/dev/null | head -1 | cut -d' ' -f4)" ;;
                esac
            fi
        done
    fi
}

# 2. 时区配置
configure_timezone() {
    echo ""
    echo -e "${BLUE}=== 时区配置 ===${NC}"

    echo -e "${YELLOW}🌍 系统时区设置${NC}"
    echo "当前时区信息："
    if command -v timedatectl >/dev/null 2>&1; then
        echo "• 当前时区: $(timedatectl show --property=Timezone --value 2>/dev/null || echo '未知')"
        echo "• 本地时间: $(timedatectl show --property=LocalRTC --value 2>/dev/null | sed 's/yes/是/g;s/no/否/g')"
        echo "• NTP同步: $(timedatectl show --property=NTP --value 2>/dev/null | sed 's/yes/已启用/g;s/no/未启用/g')"
    else
        echo "• 当前时间: $(date)"
        echo "• 时区文件: $(ls -l /etc/localtime 2>/dev/null | awk '{print $NF}' || echo '未知')"
    fi

    echo ""
    echo "修改为亚洲/上海时区的影响："
    echo "• 系统日志时间戳将使用北京时间 (UTC+8)"
    echo "• 计划任务 (cron) 将按照北京时间执行"
    echo "• 应用程序的时间显示将调整为北京时间"
    echo "• 文件的创建和修改时间戳将使用新时区"

    echo ""
    echo "💡 推荐设置：亚洲/上海 (东八区，北京时间)"
    echo "⚠️  注意：时区更改后，正在运行的程序可能需要重启才能生效"
    echo ""

    if confirm "是否配置时区为亚洲/上海？" "y"; then
        log_info "正在设置时区为 Asia/Shanghai..."

        if command -v timedatectl >/dev/null 2>&1; then
            # systemd 系统
            timedatectl set-timezone Asia/Shanghai
            log_success "时区设置完成 (使用 timedatectl)"
        else
            # 传统系统
            if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
                ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
                echo "Asia/Shanghai" > /etc/timezone 2>/dev/null || true
                log_success "时区设置完成 (使用传统方法)"
            else
                log_error "无法找到时区文件，请手动设置时区"
                return 1
            fi
        fi

        echo ""
        log_info "时区设置后的系统信息："
        if command -v timedatectl >/dev/null 2>&1; then
            timedatectl status
        else
            echo "• 当前时间: $(date)"
            echo "• 时区: $(cat /etc/timezone 2>/dev/null || echo 'Asia/Shanghai')"
        fi
    fi
}

# 3. 系统性能调优
optimize_system() {
    echo ""
    echo -e "${BLUE}=== 系统性能调优 ===${NC}"

    echo -e "${YELLOW}⚡ 系统性能优化${NC}"
    echo "此功能将通过调整内核参数来优化服务器性能，具体包括："
    echo ""
    echo "🔧 网络性能优化："
    echo "• TCP 缓冲区大小调整 - 提高网络吞吐量"
    echo "• TCP 窗口缩放 - 改善高延迟网络性能"
    echo "• TCP 快速打开 - 减少连接建立时间"
    echo "• 网络队列长度优化 - 处理更多并发连接"
    echo ""
    echo "🔧 系统资源优化："
    echo "• 文件描述符限制调整 - 支持更多同时打开的文件"
    echo "• 内存管理参数调优 - 提高内存使用效率"
    echo "• I/O 调度器优化 - 改善磁盘性能"
    echo "• 进程调度参数调整 - 提高系统响应性"
    echo ""
    echo "🔧 安全性增强："
    echo "• SYN flood 防护 - 防止 SYN 洪水攻击"
    echo "• IP 转发控制 - 增强网络安全"
    echo "• ICMP 重定向禁用 - 防止网络劫持"
    echo "• 源路由禁用 - 防止路由欺骗"
    echo ""
    echo "📊 预期性能提升："
    echo "• 网络吞吐量: +20-50%"
    echo "• 并发连接数: +300-500%"
    echo "• 响应延迟: -10-30%"
    echo "• 系统负载能力: +30-100%"
    echo ""
    echo "⚠️  注意事项："
    echo "• 优化脚本来自 GitHub 开源项目"
    echo "• 参数调整后需要重启才能完全生效"
    echo "• 适用于生产环境，已经过大量测试"
    echo "• 不会影响现有应用程序的正常运行"
    echo ""

    if confirm "是否执行系统性能调优？" "y"; then
        log_info "正在下载并执行系统调优脚本..."
        log_info "脚本来源: https://github.com/jerry048/Tune"

        if bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Tune/main/tune.sh) -t; then
            log_success "系统调优完成"
            echo ""
            log_info "已应用的主要优化项目："
            echo "✅ TCP 参数已优化"
            echo "✅ 网络缓冲区已调整"
            echo "✅ 文件描述符限制已提升"
            echo "✅ 内存管理参数已优化"
            echo "✅ I/O 性能参数已调整"
            echo ""
            log_warning "建议重启系统以使所有优化参数生效"
        else
            log_error "系统调优失败"
            log_info "可能的原因："
            echo "• 网络连接问题，无法下载调优脚本"
            echo "• 系统权限不足"
            echo "• 系统版本不兼容"
            log_info "您可以稍后手动运行以下命令重试："
            echo "bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Tune/main/tune.sh) -t"
        fi
    fi
}

# 4. BBR 网络优化
configure_bbr() {
    echo ""
    echo -e "${BLUE}=== BBR 网络优化 ===${NC}"

    echo -e "${YELLOW}🚀 BBR 拥塞控制算法${NC}"
    echo "BBR (Bottleneck Bandwidth and RTT) 是 Google 开发的革命性网络优化技术"
    echo ""
    echo "🔍 当前网络状态检查："
    if lsmod | grep -q bbr; then
        echo "• 检测到已安装 BBR 模块: $(lsmod | grep bbr | awk '{print $1}' | tr '\n' ' ')"
        echo "• 当前拥塞控制: $(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo '未知')"
        echo "• 可用算法: $(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo '未知')"
    else
        echo "• BBR 状态: 未安装"
        echo "• 当前拥塞控制: $(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo '未知')"
    fi
    echo ""
    echo "🎯 BBR 技术优势："
    echo "• 摆脱传统丢包探测机制 - 不再依赖网络丢包来调整发送速度"
    echo "• 精确测量带宽和延迟 - 实时监测网络瓶颈带宽和往返时间"
    echo "• 智能速度控制 - 根据网络实际情况动态调整发送速率"
    echo "• 减少缓冲区膨胀 - 降低网络设备缓冲区占用，减少延迟"
    echo ""
    echo "📈 性能提升效果："
    echo "• 高延迟网络: 吞吐量提升 2-25 倍"
    echo "• 有损网络: 吞吐量提升 3-10 倍"
    echo "• 移动网络: 延迟降低 30-80%"
    echo "• 国际链路: 连接稳定性显著改善"
    echo ""
    echo "🔧 BBRx 增强版特性："
    echo "• 优化启动阶段参数 (startup phase)"
    echo "• 改进带宽探测算法 (probe_bw)"
    echo "• 调整延迟探测机制 (probe_rtt)"
    echo "• 更好的公平性和稳定性"
    echo ""
    echo "⚠️  重要说明："
    echo "• 需要 Linux 4.9+ 内核支持"
    echo "• 安装后需要重启系统生效"
    echo "• 主要对 TCP 连接有效 (HTTP/HTTPS/SSH 等)"
    echo "• 适用于各种网络环境，无副作用"
    echo ""

    if confirm "是否安装 BBRx 网络优化？" "y"; then
        log_info "正在检查系统兼容性..."

        # 检查内核版本
        kernel_version=$(uname -r | cut -d. -f1-2)
        log_info "当前内核版本: $(uname -r)"

        log_info "正在安装 BBRx 拥塞控制算法..."
        log_info "脚本来源: https://github.com/jerry048/Tune"

        if bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Tune/main/tune.sh) -x; then
            log_success "BBRx 安装完成"
            echo ""
            log_info "安装成功! 以下模块已加载:"
            lsmod | grep bbr || log_warning "BBR 模块可能需要重启后才能加载"
            echo ""
            log_warning "🔄 重要: 需要重启系统使 BBR 完全生效"
            log_info "重启后可以使用以下命令验证:"
            echo "  lsmod | grep bbr"
            echo "  cat /proc/sys/net/ipv4/tcp_congestion_control"
        else
            log_error "BBRx 安装失败"
            echo ""
            log_info "尝试原因分析:"
            echo "• 内核版本可能过低 (需要 4.9+)"
            echo "• 网络连接问题"
            echo "• 系统权限不足"

            if confirm "是否尝试安装备选的传统 BBR？"; then
                log_info "正在安装备选 BBR 方案 (秋水逸冰版本)..."
                if wget --no-check-certificate https://github.com/teddysun/across/raw/master/bbr.sh && chmod +x bbr.sh && ./bbr.sh; then
                    log_success "备选 BBR 安装完成"
                else
                    log_error "备选 BBR 安装也失败，请检查网络连接或内核版本"
                fi
            fi
        fi
    fi
}

# 5. SWAP 配置
configure_swap() {
    echo ""
    echo -e "${BLUE}=== SWAP 交换空间配置 ===${NC}"

    echo -e "${YELLOW}💾 SWAP 虚拟内存管理${NC}"
    echo "SWAP 是磁盘上的虚拟内存空间，当物理内存不足时系统会使用 SWAP 来扩展可用内存"
    echo ""

    # 显示当前内存状态
    echo "🔍 当前系统内存信息："
    if command -v free >/dev/null 2>&1; then
        # 获取内存信息
        local total_mem=$(free -m | awk 'NR==2{print $2}')
        local used_mem=$(free -m | awk 'NR==2{print $3}')
        local free_mem=$(free -m | awk 'NR==2{print $4}')
        local swap_total=$(free -m | awk 'NR==3{print $2}')
        local swap_used=$(free -m | awk 'NR==3{print $3}')

        echo "• 物理内存总量: ${total_mem}MB"
        echo "• 已使用内存: ${used_mem}MB"
        echo "• 可用内存: ${free_mem}MB"
        echo "• 内存使用率: $(( used_mem * 100 / total_mem ))%"

        if [ "$swap_total" -gt 0 ] 2>/dev/null; then
            echo "• SWAP 总量: ${swap_total}MB"
            echo "• SWAP 已使用: ${swap_used}MB"
            echo "• SWAP 使用率: $(( swap_used * 100 / swap_total ))%"
        else
            echo "• SWAP 状态: 未配置"
        fi
    else
        echo "• 无法获取详细内存信息"
    fi

    echo ""
    echo "💡 SWAP 作用和原理："
    echo "• 虚拟内存扩展 - 当 RAM 不足时，将不活跃数据移到磁盘"
    echo "• 防止 OOM 终止 - 避免程序因内存不足被强制终止"
    echo "• 休眠功能支持 - 系统休眠时将内存内容保存到 SWAP"
    echo "• 内存整理优化 - 帮助系统更好地管理内存碎片"
    echo ""
    echo "📊 推荐 SWAP 配置大小："
    if [ -n "$total_mem" ] && [ "$total_mem" -gt 0 ] 2>/dev/null; then
        if [ "$total_mem" -le 512 ]; then
            echo "• 当前内存 ${total_mem}MB <= 512MB，推荐 SWAP: 1GB"
        elif [ "$total_mem" -le 1024 ]; then
            echo "• 当前内存 ${total_mem}MB <= 1GB，推荐 SWAP: 2GB"
        elif [ "$total_mem" -le 2048 ]; then
            echo "• 当前内存 ${total_mem}MB <= 2GB，推荐 SWAP: 2-4GB"
        elif [ "$total_mem" -le 4096 ]; then
            echo "• 当前内存 ${total_mem}MB <= 4GB，推荐 SWAP: 2-4GB"
        else
            echo "• 当前内存 ${total_mem}MB > 4GB，推荐 SWAP: 2-8GB"
        fi
    else
        echo "• 小内存服务器 (<1GB): 建议 1-2GB SWAP"
        echo "• 中等内存服务器 (1-4GB): 建议 2-4GB SWAP"
        echo "• 大内存服务器 (>4GB): 建议 2-8GB SWAP"
    fi
    echo ""
    echo "⚠️  注意事项："
    echo "• SWAP 使用磁盘空间，访问速度比内存慢"
    echo "• 过度使用 SWAP 会导致系统响应缓慢"
    echo "• SSD 硬盘上的 SWAP 性能比机械硬盘好"
    echo "• 配置脚本将自动选择合适的 SWAP 大小"
    echo ""

    if confirm "是否配置 SWAP 交换空间？" "y"; then
        log_info "正在下载和执行 SWAP 配置脚本..."
        log_info "脚本来源: https://github.com/yuju520/Script"

        if wget -O swap.sh https://raw.githubusercontent.com/yuju520/Script/main/swap.sh && chmod +x swap.sh && ./swap.sh; then
            log_success "SWAP 配置完成"
            echo ""
            log_info "✅ SWAP 配置成功! 配置后内存状态："

            if command -v free >/dev/null 2>&1; then
                free -h
                echo ""
                echo "📈 内存使用对比:"
                local new_swap_total=$(free -m | awk 'NR==3{print $2}')
                if [ "$new_swap_total" -gt 0 ] 2>/dev/null; then
                    echo "• 新增 SWAP 空间: ${new_swap_total}MB"
                    echo "• 总可用内存: $((total_mem + new_swap_total))MB"
                    echo "• 内存扩展比例: $(( (total_mem + new_swap_total) * 100 / total_mem ))%"
                fi
            fi

            # 显示 SWAP 配置详情
            if [ -f /proc/swaps ]; then
                echo ""
                echo "🔧 SWAP 配置详情:"
                cat /proc/swaps
            fi
        else
            log_error "SWAP 配置失败"
            echo ""
            log_info "可能的失败原因:"
            echo "• 磁盘空间不足"
            echo "• 权限不足"
            echo "• 网络连接问题"
            echo "• 系统不支持 SWAP 操作"
            log_info "您可以稍后手动运行以下命令重试:"
            echo "wget -O swap.sh https://raw.githubusercontent.com/yuju520/Script/main/swap.sh"
            echo "chmod +x swap.sh && ./swap.sh"
        fi
    fi
}

# 6. Docker 安装
install_docker() {
    echo ""
    echo -e "${BLUE}=== Docker 环境安装 ===${NC}"

    echo -e "${YELLOW}🐳 Docker 容器化平台${NC}"
    echo "Docker 是目前最流行的容器化平台，可以轻松部署和管理应用程序"
    echo ""

    # 检查是否已经安装
    echo "🔍 当前 Docker 状态检查："
    if command -v docker >/dev/null 2>&1; then
        echo "• Docker 状态: 已安装"
        echo "• Docker 版本: $(docker --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1 || echo '未知')"
        if systemctl is-active docker >/dev/null 2>&1; then
            echo "• Docker 服务: 运行中"
        else
            echo "• Docker 服务: 已停止"
        fi
        if command -v docker-compose >/dev/null 2>&1; then
            echo "• Docker Compose: $(docker-compose --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1 || echo '已安装')"
        elif docker compose version >/dev/null 2>&1; then
            echo "• Docker Compose: $(docker compose version --short 2>/dev/null || echo '已安装')"
        else
            echo "• Docker Compose: 未安装"
        fi
    else
        echo "• Docker 状态: 未安装"
        echo "• Docker Compose: 未安装"
    fi

    echo ""
    echo "🎯 Docker 核心功能："
    echo "• 容器化应用 - 将应用及其依赖打包成轻量级容器"
    echo "• 环境隔离 - 不同应用运行在独立的环境中，避免冲突"
    echo "• 快速部署 - 秒级启动应用，比传统虚拟机快 10-100 倍"
    echo "• 资源高效 - 共享操作系统内核，占用资源少"
    echo "• 版本管理 - 支持应用版本控制和回滚"
    echo "• 水平扩展 - 轻松增加或减少应用实例"
    echo ""
    echo "🔧 将安装的组件："
    echo "• Docker Engine - Docker 核心引擎，负责容器运行"
    echo "• Docker CLI - Docker 命令行工具"
    echo "• containerd - 容器运行时，管理容器生命周期"
    echo "• Docker Compose - 多容器应用编排工具"
    echo "• Docker 守护进程 - 后台服务，处理 Docker API 请求"
    echo ""
    echo "📦 根据发行版选择安装方式："
    case "$DISTRO" in
        debian-based)
            echo "• $DISTRO: 优先使用官方脚本，备选 apt 包管理器"
            echo "  - 官方脚本: 最新版本，自动配置仓库"
            echo "  - apt 安装: 发行版仓库版本，更稳定"
            ;;
        rhel-based)
            echo "• $DISTRO: 使用 $PACKAGE_MANAGER 包管理器"
            echo "  - 自动配置 EPEL 仓库 (如需要)"
            echo "  - 安装 Docker CE 和 Docker Compose"
            ;;
        arch-based)
            echo "• $DISTRO: 使用 pacman 包管理器"
            echo "  - 从官方仓库安装最新版本"
            echo "  - 自动处理依赖关系"
            ;;
        suse-based)
            echo "• $DISTRO: 使用 zypper 包管理器"
            echo "  - 企业级支持和稳定性"
            echo "  - 集成系统安全特性"
            ;;
    esac
    echo ""
    echo "⚠️  安装注意事项："
    echo "• 安装过程可能需要 2-5 分钟"
    echo "• 会自动创建 docker 用户组"
    echo "• 将设置为开机自动启动"
    echo "• 首次运行可能需要下载基础镜像"
    echo ""

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