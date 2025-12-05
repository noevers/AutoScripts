#!/bin/bash
# xmrig CPU利用率一键控制脚本 v2.0
# 整合版：包含安装、配置、控制、服务管理功能

CONFIG_FILE="/etc/xmrig-cpulimit.conf"
LOG_FILE="/var/log/xmrig-cpulimit.log"
SERVICE_FILE="/etc/systemd/system/xmrig-cpulimit.service"
SCRIPT_PATH="/usr/local/bin/xmrig-cpulimit.sh"
DEFAULT_CPU_LIMIT=50

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 加载配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        echo -e "${YELLOW}配置文件不存在，使用默认配置${NC}"
        XMrig_PATH="/usr/local/bin/xmrig"
        XMrig_ARGS="-o pool.monero.hashvault.pro:443 -u YOUR_WALLET_ADDRESS -p x --tls"
        DEFAULT_CPU_LIMIT=50
    fi
}

# 写日志
log_message() {
    local msg="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $msg" >> "$LOG_FILE"
    echo "$msg"
}

# 获取CPU核心数
get_cpu_cores() {
    grep -c "^processor" /proc/cpuinfo
}

# 计算cpulimit值
calculate_cpulimit_value() {
    local cpu_limit=$1
    local cpu_cores=$(get_cpu_cores)
    echo $((cpu_cores * cpu_limit))
}

# 检查进程是否运行
check_xmrig_running() {
    pgrep -f "xmrig" > /dev/null 2>&1
}

check_cpulimit_running() {
    pgrep -f "cpulimit -e xmrig" > /dev/null 2>&1
}

# 显示状态
show_status() {
    echo -e "\n${BLUE}========== xmrig CPU限制控制状态 ==========${NC}"
    echo "CPU核心数: $(get_cpu_cores)"
    
    if check_xmrig_running; then
        xmrig_pid=$(pgrep -f "xmrig")
        echo -e "xmrig状态: ${GREEN}运行中${NC} (PID: $xmrig_pid)"
        
        cpu_usage=$(ps -p $xmrig_pid -o %cpu 2>/dev/null | tail -1 | awk '{print $1}')
        echo "当前CPU使用率: ${cpu_usage}%"
        
        if check_cpulimit_running; then
            cpulimit_pid=$(pgrep -f "cpulimit -e xmrig")
            echo -e "cpulimit状态: ${GREEN}运行中${NC} (PID: $cpulimit_pid)"
            cpulimit_cmd=$(ps -p $cpulimit_pid -o cmd 2>/dev/null | tail -1)
            echo "限制命令: $cpulimit_cmd"
        else
            echo -e "cpulimit状态: ${RED}未运行${NC}"
        fi
    else
        echo -e "xmrig状态: ${RED}未运行${NC}"
    fi
    
    # 检查服务状态
    if systemctl is-enabled xmrig-cpulimit 2>/dev/null | grep -q enabled; then
        echo -e "开机自启: ${GREEN}已启用${NC}"
    else
        echo -e "开机自启: ${RED}未启用${NC}"
    fi
    
    # 配置文件信息
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "配置文件: ${GREEN}$CONFIG_FILE${NC}"
    else
        echo -e "配置文件: ${RED}未找到${NC}"
    fi
    echo -e "${BLUE}============================================${NC}\n"
}

# 启动xmrig
start_xmrig() {
    local cpu_limit=${1:-$DEFAULT_CPU_LIMIT}
    
    load_config
    
    if check_xmrig_running; then
        echo -e "${YELLOW}xmrig已经在运行${NC}"
        return 1
    fi
    
    if ! command -v cpulimit &> /dev/null; then
        echo -e "${RED}错误: cpulimit未安装${NC}"
        echo "请先运行: $0 install 进行安装"
        return 1
    fi
    
    if [ ! -f "$XMrig_PATH" ]; then
        echo -e "${RED}错误: xmrig未找到: $XMrig_PATH${NC}"
        return 1
    fi
    
    local cpulimit_value=$(calculate_cpulimit_value "$cpu_limit")
    
    echo -e "${GREEN}启动xmrig，CPU限制: ${cpu_limit}% (总核心限制: ${cpulimit_value}%)${NC}"
    log_message "启动xmrig，CPU限制: ${cpu_limit}%"
    
    # 启动xmrig
    nohup "$XMrig_PATH" $XMrig_ARGS > /dev/null 2>&1 &
    
    sleep 2
    
    # 启动cpulimit
    cpulimit -e "$(basename $XMrig_PATH)" -l "$cpulimit_value" > /dev/null 2>&1 &
    
    # 保存PID
    pgrep -f "xmrig" > /var/run/xmrig.pid 2>/dev/null
    pgrep -f "cpulimit -e xmrig" > /var/run/xmrig-cpulimit.pid 2>/dev/null
    
    echo -e "${GREEN}启动完成！${NC}"
    show_status
}

# 停止xmrig
stop_xmrig() {
    echo -e "${YELLOW}停止xmrig和cpulimit...${NC}"
    log_message "停止xmrig"
    
    if check_cpulimit_running; then
        pkill -f "cpulimit -e xmrig"
        echo "已停止cpulimit"
    fi
    
    if check_xmrig_running; then
        pkill -f "xmrig"
        sleep 1
        if check_xmrig_running; then
            pkill -9 -f "xmrig"
        fi
        echo "已停止xmrig"
    fi
    
    rm -f /var/run/xmrig.pid /var/run/xmrig-cpulimit.pid
    echo -e "${GREEN}已停止所有相关进程${NC}"
}

# 安装功能
install_all() {
    echo -e "${GREEN}开始安装xmrig CPU限制控制脚本...${NC}"
    
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}请使用root权限运行安装${NC}"
        exit 1
    fi
    
    # 1. 安装cpulimit
    echo "安装cpulimit..."
    apt-get update
    apt-get install -y cpulimit
    
    # 2. 创建配置文件
    echo "创建配置文件..."
    cat > "$CONFIG_FILE" << 'EOF'
# xmrig CPU限制配置
# xmrig可执行文件路径
XMrig_PATH="/usr/local/bin/xmrig"

# 默认CPU利用率 (1-100)
DEFAULT_CPU_LIMIT=50

# xmrig启动参数（请根据实际情况修改）
# 示例：XMRig挖矿参数
# XMrig_ARGS="-o pool.monero.hashvault.pro:443 -u YOUR_WALLET_ADDRESS -p x --tls"

# 示例：CPU挖矿测试参数（请先测试使用）
XMrig_ARGS="--donate-level 1 -o pool.monero.hashvault.pro:443 -u 48edfHu7V9Z84YzzMa6fUueoELZ9ZRXq9VetWzYGzKt52XU5xvqgzYnDK9URnRoJMk1j8nLwEVsaSWJ4fhdUyZijBGUicoD -p x --tls --coin=monero"
EOF
    
    echo -e "${YELLOW}请编辑 $CONFIG_FILE 配置你的xmrig参数${NC}"
    echo -e "${YELLOW}特别是钱包地址和矿池地址${NC}"
    
    # 3. 创建日志文件
    echo "创建日志文件..."
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    # 4. 复制脚本到系统目录
    echo "安装控制脚本..."
    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    # 5. 创建systemd服务文件
    echo "创建systemd服务..."
    cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=xmrig CPU限制服务
After=network.target
Wants=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/xmrig-cpulimit.sh start
ExecStop=/usr/local/bin/xmrig-cpulimit.sh stop
ExecReload=/usr/local/bin/xmrig-cpulimit.sh restart
Restart=on-failure
RestartSec=10
User=root
Group=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    
    echo -e "\n${GREEN}安装完成！${NC}"
    echo -e "\n${BLUE}================== 使用说明 ==================${NC}"
    echo "1. 首先编辑配置文件："
    echo "   nano $CONFIG_FILE"
    echo "   修改XMrig_PATH和XMrig_ARGS为你的实际配置"
    echo ""
    echo "2. 常用命令："
    echo "   # 启动并限制CPU为60%"
    echo "   xmrig-cpulimit.sh 60 start"
    echo ""
    echo "   # 停止"
    echo "   xmrig-cpulimit.sh stop"
    echo ""
    echo "   # 查看状态"
    echo "   xmrig-cpulimit.sh status"
    echo ""
    echo "   # 重启"
    echo "   xmrig-cpulimit.sh restart"
    echo ""
    echo "3. 服务管理："
    echo "   # 启用开机自启动"
    echo "   xmrig-cpulimit.sh enable"
    echo ""
    echo "   # 禁用开机自启动"
    echo "   xmrig-cpulimit.sh disable"
    echo ""
    echo "   # 启动服务"
    echo "   systemctl start xmrig-cpulimit"
    echo ""
    echo "   # 停止服务"
    echo "   systemctl stop xmrig-cpulimit"
    echo ""
    echo "4. 查看日志："
    echo "   tail -f $LOG_FILE"
    echo "   journalctl -u xmrig-cpulimit"
    echo -e "${BLUE}============================================${NC}\n"
    
    log_message "安装完成"
}

# 启用开机自启动
enable_service() {
    if [ -f "$SERVICE_FILE" ]; then
        systemctl enable xmrig-cpulimit
        echo -e "${GREEN}已启用开机自启动${NC}"
    else
        echo -e "${RED}服务文件不存在，请先运行安装${NC}"
        exit 1
    fi
}

# 禁用开机自启动
disable_service() {
    if [ -f "$SERVICE_FILE" ]; then
        systemctl disable xmrig-cpulimit
        echo -e "${YELLOW}已禁用开机自启动${NC}"
    else
        echo -e "${RED}服务文件不存在${NC}"
        exit 1
    fi
}

# 显示帮助
show_help() {
    echo -e "${BLUE}================== xmrig CPU限制控制脚本 ==================${NC}"
    echo "一个整合的脚本，用于控制xmrig的CPU使用率并支持开机自启动"
    echo ""
    echo "使用方法: $0 [选项] [参数]"
    echo ""
    echo "选项:"
    echo "  install                    安装脚本和依赖"
    echo "  [CPU百分比] start          启动xmrig并限制CPU使用率"
    echo "  stop                       停止xmrig"
    echo "  restart                    重启xmrig"
    echo "  status                     查看当前状态"
    echo "  enable                     启用开机自启动"
    echo "  disable                    禁用开机自启动"
    echo "  help                       显示此帮助信息"
    echo "  log                        查看日志"
    echo "  config                     编辑配置文件"
    echo ""
    echo "示例:"
    echo "  $0 install                 首次安装"
    echo "  $0 75 start                启动并限制CPU为75%"
    echo "  $0 stop                    停止"
    echo "  $0 status                  查看状态"
    echo "  $0 enable                  启用开机自启动"
    echo ""
    echo "注意事项:"
    echo "  1. 首次使用前请运行: $0 install"
    echo "  2. 安装后编辑配置文件: $CONFIG_FILE"
    echo "  3. 配置正确的xmrig路径和挖矿参数"
    echo -e "${BLUE}========================================================${NC}"
}

# 查看日志
show_log() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${BLUE}=== 最后50行日志 ===${NC}"
        tail -n 50 "$LOG_FILE"
        echo -e "${BLUE}===================${NC}"
    else
        echo -e "${YELLOW}日志文件不存在${NC}"
    fi
}

# 编辑配置
edit_config() {
    if command -v nano &> /dev/null; then
        nano "$CONFIG_FILE"
    elif command -v vim &> /dev/null; then
        vim "$CONFIG_FILE"
    elif command -v vi &> /dev/null; then
        vi "$CONFIG_FILE"
    else
        echo -e "${RED}未找到文本编辑器，请手动编辑: $CONFIG_FILE${NC}"
        cat "$CONFIG_FILE"
    fi
}

# 主函数
main() {
    case "$1" in
        install)
            install_all
            ;;
        start)
            # 检查第二个参数是否是数字
            if [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -le 100 ] && [ "$2" -ge 1 ]; then
                start_xmrig "$2"
            else
                start_xmrig
            fi
            ;;
        stop)
            stop_xmrig
            ;;
        restart)
            stop_xmrig
            sleep 2
            if [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -le 100 ] && [ "$2" -ge 1 ]; then
                start_xmrig "$2"
            else
                start_xmrig
            fi
            ;;
        status)
            show_status
            ;;
        enable)
            enable_service
            ;;
        disable)
            disable_service
            ;;
        log)
            show_log
            ;;
        config)
            edit_config
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            # 如果第一个参数是数字，则作为CPU限制值
            if [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -le 100 ] && [ "$1" -ge 1 ]; then
                if [ "$2" == "start" ]; then
                    start_xmrig "$1"
                elif [ "$2" == "restart" ]; then
                    stop_xmrig
                    sleep 2
                    start_xmrig "$1"
                else
                    echo -e "${YELLOW}用法: $0 [CPU百分比] [start|restart]${NC}"
                    echo "示例: $0 75 start"
                fi
            elif [ -z "$1" ]; then
                show_help
            else
                echo -e "${RED}未知选项: $1${NC}"
                show_help
                exit 1
            fi
            ;;
    esac
}

# 检查是否以root运行需要root权限的命令
check_root_for_admin_commands() {
    local cmd="$1"
    local root_commands="install enable disable"
    
    for root_cmd in $root_commands; do
        if [ "$cmd" == "$root_cmd" ]; then
            if [ "$EUID" -ne 0 ]; then 
                echo -e "${RED}此命令需要root权限，请使用: sudo $0 $cmd${NC}"
                exit 1
            fi
        fi
    done
}

# 运行脚本
if [ $# -ge 1 ]; then
    check_root_for_admin_commands "$1"
fi

main "$@"
