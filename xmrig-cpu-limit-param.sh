#!/bin/bash
# xmrig CPU利用率控制脚本 - 完整功能版（无需配置xmrig）
# 用于控制已安装xmrig的CPU使用率，支持重启自动启动

SCRIPT_PATH="/usr/local/bin/xmrig-cpulimit.sh"
SERVICE_FILE="/etc/systemd/system/xmrig-cpulimit.service"
PID_FILE_XMRIG="/var/run/xmrig.pid"
PID_FILE_CPULIMIT="/var/run/xmrig-cpulimit.pid"
LOG_FILE="/var/log/xmrig-cpulimit.log"
DEFAULT_CPU_LIMIT=50

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 检查xmrig是否在运行
check_xmrig_running() {
    pgrep -x "xmrig" > /dev/null 2>&1
    return $?
}

# 检查cpulimit是否在运行
check_cpulimit_running() {
    pgrep -f "cpulimit -e xmrig" > /dev/null 2>&1
    return $?
}

# 获取xmrig进程信息
get_xmrig_info() {
    if check_xmrig_running; then
        local pid=$(pgrep -x "xmrig")
        local cpu_usage=$(ps -p $pid -o %cpu 2>/dev/null | tail -1 | awk '{print $1}')
        local cmd=$(ps -p $pid -o cmd 2>/dev/null | tail -1)
        echo "$pid:$cpu_usage:$cmd"
    fi
}

# 获取cpulimit进程信息
get_cpulimit_info() {
    if check_cpulimit_running; then
        local pid=$(pgrep -f "cpulimit -e xmrig")
        local cmd=$(ps -p $pid -o cmd 2>/dev/null | tail -1)
        echo "$pid:$cmd"
    fi
}

# 显示状态
show_status() {
    echo -e "\n${BLUE}========== xmrig CPU限制控制状态 ==========${NC}"
    echo "系统时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "CPU核心数: $(get_cpu_cores)"
    
    # xmrig状态
    if check_xmrig_running; then
        local xmrig_info=$(get_xmrig_info)
        local pid=$(echo $xmrig_info | cut -d: -f1)
        local cpu_usage=$(echo $xmrig_info | cut -d: -f2)
        local cmd=$(echo $xmrig_info | cut -d: -f3)
        
        echo -e "xmrig状态: ${GREEN}运行中${NC} (PID: $pid)"
        echo "当前CPU使用率: ${cpu_usage}%"
        echo "运行命令: $cmd"
    else
        echo -e "xmrig状态: ${RED}未运行${NC}"
    fi
    
    # cpulimit状态
    if check_cpulimit_running; then
        local cpulimit_info=$(get_cpulimit_info)
        local pid=$(echo $cpulimit_info | cut -d: -f1)
        local cmd=$(echo $cpulimit_info | cut -d: -f2)
        
        echo -e "cpulimit状态: ${GREEN}运行中${NC} (PID: $pid)"
        echo "限制命令: $cmd"
        
        # 解析CPU限制值
        if [[ $cmd =~ -l[[:space:]]+([0-9]+) ]]; then
            local total_limit="${BASH_REMATCH[1]}"
            local cpu_cores=$(get_cpu_cores)
            local per_core_limit=$((total_limit / cpu_cores))
            echo "CPU限制设置: ${per_core_limit}% 每核心 (总计: ${total_limit}%)"
        fi
    else
        echo -e "cpulimit状态: ${YELLOW}未运行${NC}"
    fi
    
    # 检查服务状态
    if [ -f "$SERVICE_FILE" ]; then
        if systemctl is-enabled xmrig-cpulimit 2>/dev/null | grep -q enabled; then
            echo -e "开机自启: ${GREEN}已启用${NC}"
        else
            echo -e "开机自启: ${YELLOW}未启用${NC}"
        fi
    fi
    
    # 检查日志
    if [ -f "$LOG_FILE" ]; then
        local log_size=$(du -h "$LOG_FILE" | cut -f1)
        echo "日志文件: $LOG_FILE ($log_size)"
    fi
    
    echo -e "${BLUE}============================================${NC}\n"
}

# 启动CPU限制
start_cpulimit() {
    local cpu_limit=${1:-$DEFAULT_CPU_LIMIT}
    
    # 参数验证
    if ! [[ "$cpu_limit" =~ ^[0-9]+$ ]] || [ "$cpu_limit" -lt 1 ] || [ "$cpu_limit" -gt 100 ]; then
        log_message "${RED}错误: CPU限制必须在1-100之间${NC}"
        exit 1
    fi
    
    # 检查xmrig是否在运行
    if ! check_xmrig_running; then
        log_message "${RED}错误: xmrig未在运行，请先启动xmrig${NC}"
        exit 1
    fi
    
    # 检查cpulimit是否已安装
    if ! command -v cpulimit &> /dev/null; then
        log_message "${RED}错误: cpulimit未安装${NC}"
        echo "安装命令: sudo apt-get install cpulimit"
        exit 1
    fi
    
    # 停止现有的cpulimit进程
    if check_cpulimit_running; then
        log_message "${YELLOW}停止现有的cpulimit进程...${NC}"
        pkill -f "cpulimit -e xmrig"
        sleep 1
    fi
    
    # 计算总限制值
    local cpu_cores=$(get_cpu_cores)
    local total_limit=$(calculate_cpulimit_value "$cpu_limit")
    local xmrig_pid=$(pgrep -x "xmrig")
    
    log_message "${GREEN}启动CPU限制...${NC}"
    log_message "CPU核心数: $cpu_cores"
    log_message "每核心限制: ${cpu_limit}%"
    log_message "总计限制: ${total_limit}%"
    log_message "xmrig PID: $xmrig_pid"
    
    # 启动cpulimit
    if cpulimit -e xmrig -l "$total_limit" > /dev/null 2>&1 & then
        local cpulimit_pid=$!
        sleep 1
        
        # 检查是否启动成功
        if ps -p $cpulimit_pid > /dev/null 2>&1; then
            echo "$cpulimit_pid" > "$PID_FILE_CPULIMIT"
            log_message "${GREEN}✓ CPU限制已启动 (PID: $cpulimit_pid)${NC}"
            
            # 保存当前限制值供重启使用
            echo "$cpu_limit" > /tmp/xmrig_cpu_limit.last
            log_message "CPU限制值 $cpu_limit% 已保存"
            
            show_status
        else
            log_message "${RED}✗ CPU限制启动失败${NC}"
            exit 1
        fi
    else
        log_message "${RED}✗ 启动cpulimit失败${NC}"
        exit 1
    fi
}

# 停止CPU限制
stop_cpulimit() {
    log_message "${YELLOW}停止CPU限制...${NC}"
    
    local stopped=0
    
    # 停止cpulimit进程
    if check_cpulimit_running; then
        pkill -f "cpulimit -e xmrig"
        sleep 1
        
        # 确认是否停止
        if check_cpulimit_running; then
            pkill -9 -f "cpulimit -e xmrig"
            log_message "强制停止cpulimit"
        fi
        
        rm -f "$PID_FILE_CPULIMIT"
        log_message "已停止CPU限制"
        stopped=1
    fi
    
    # 删除PID文件
    [ -f "$PID_FILE_CPULIMIT" ] && rm -f "$PID_FILE_CPULIMIT"
    
    if [ $stopped -eq 1 ]; then
        log_message "${GREEN}✓ CPU限制已停止${NC}"
    else
        log_message "没有运行的CPU限制进程"
    fi
    
    show_status
}

# 重启CPU限制
restart_cpulimit() {
    local cpu_limit=${1:-$DEFAULT_CPU_LIMIT}
    
    log_message "${YELLOW}重启CPU限制...${NC}"
    
    # 检查是否有保存的上次限制值
    if [ -z "$1" ] && [ -f "/tmp/xmrig_cpu_limit.last" ]; then
        cpu_limit=$(cat /tmp/xmrig_cpu_limit.last)
        log_message "使用上次的CPU限制值: ${cpu_limit}%"
    fi
    
    stop_cpulimit
    sleep 2
    start_cpulimit "$cpu_limit"
}

# 安装脚本和服务
install_script() {
    local cpu_limit=${1:-$DEFAULT_CPU_LIMIT}
    
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then 
        log_message "${RED}请使用root权限运行安装${NC}"
        exit 1
    fi
    
    log_message "${GREEN}开始安装xmrig CPU限制控制脚本...${NC}"
    
    # 验证CPU限制参数
    if ! [[ "$cpu_limit" =~ ^[0-9]+$ ]] || [ "$cpu_limit" -lt 1 ] || [ "$cpu_limit" -gt 100 ]; then
        log_message "${RED}错误: CPU限制必须在1-100之间${NC}"
        exit 1
    fi
    
    # 1. 安装cpulimit
    log_message "安装cpulimit..."
    apt-get update > /dev/null 2>&1
    if apt-get install -y cpulimit > /dev/null 2>&1; then
        log_message "${GREEN}✓ cpulimit安装成功${NC}"
    else
        log_message "${RED}✗ cpulimit安装失败${NC}"
        exit 1
    fi
    
    # 2. 创建日志文件
    log_message "创建日志文件..."
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    log_message "日志文件: $LOG_FILE"
    
    # 3. 复制脚本到系统目录
    log_message "安装控制脚本..."
    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    log_message "脚本安装到: $SCRIPT_PATH"
    
    # 4. 创建systemd服务文件
    log_message "创建systemd服务..."
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=xmrig CPU限制服务
Description=自动限制已运行xmrig的CPU使用率
After=network.target
Requires=network.target

[Service]
Type=forking
# 启动服务时应用CPU限制
ExecStart=$SCRIPT_PATH service-start $cpu_limit
# 停止服务时移除CPU限制
ExecStop=$SCRIPT_PATH service-stop
# 重启服务
ExecReload=$SCRIPT_PATH service-restart
Restart=on-failure
RestartSec=10
User=root
Group=root
StandardOutput=journal
StandardError=journal
# 保存PID文件
PIDFile=$PID_FILE_CPULIMIT

[Install]
WantedBy=multi-user.target
EOF
    
    # 5. 重新加载systemd
    systemctl daemon-reload
    
    # 6. 启用服务
    systemctl enable xmrig-cpulimit > /dev/null 2>&1
    
    # 7. 保存默认CPU限制
    echo "$cpu_limit" > /etc/xmrig-cpu-limit.default
    
    log_message "${GREEN}安装完成！${NC}"
    
    # 显示安装信息
    echo -e "\n${BLUE}================== 安装信息 ==================${NC}"
    echo "脚本路径: $SCRIPT_PATH"
    echo "服务文件: $SERVICE_FILE"
    echo "日志文件: $LOG_FILE"
    echo "默认CPU限制: ${cpu_limit}%"
    echo ""
    echo "服务状态:"
    systemctl status xmrig-cpulimit --no-pager -l
    echo -e "${BLUE}============================================${NC}"
    
    # 显示使用说明
    show_usage
}

# 卸载脚本和服务
uninstall_script() {
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then 
        log_message "${RED}请使用root权限运行卸载${NC}"
        exit 1
    fi
    
    log_message "${YELLOW}开始卸载xmrig CPU限制控制...${NC}"
    
    # 1. 停止服务
    if systemctl is-active xmrig-cpulimit > /dev/null 2>&1; then
        log_message "停止服务..."
        systemctl stop xmrig-cpulimit
    fi
    
    # 2. 禁用服务
    if systemctl is-enabled xmrig-cpulimit > /dev/null 2>&1; then
        log_message "禁用服务..."
        systemctl disable xmrig-cpulimit
    fi
    
    # 3. 删除服务文件
    if [ -f "$SERVICE_FILE" ]; then
        log_message "删除服务文件..."
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi
    
    # 4. 删除脚本
    if [ -f "$SCRIPT_PATH" ]; then
        log_message "删除控制脚本..."
        rm -f "$SCRIPT_PATH"
    fi
    
    # 5. 删除配置文件
    [ -f "/etc/xmrig-cpu-limit.default" ] && rm -f "/etc/xmrig-cpu-limit.default"
    
    # 6. 删除PID文件
    [ -f "$PID_FILE_CPULIMIT" ] && rm -f "$PID_FILE_CPULIMIT"
    [ -f "$PID_FILE_XMRIG" ] && rm -f "$PID_FILE_XMRIG"
    
    # 7. 删除临时文件
    [ -f "/tmp/xmrig_cpu_limit.last" ] && rm -f "/tmp/xmrig_cpu_limit.last"
    
    # 8. 保留日志文件供参考（可选）
    log_message "日志文件保留在: $LOG_FILE"
    
    log_message "${GREEN}卸载完成！${NC}"
    
    echo -e "\n${YELLOW}注意:${NC}"
    echo "- 日志文件 $LOG_FILE 已被保留"
    echo "- cpulimit软件包未被移除，如需移除请手动执行: apt-get remove cpulimit"
    echo "- xmrig进程不受影响，继续运行"
}

# 启用服务
enable_service() {
    if [ ! -f "$SERVICE_FILE" ]; then
        log_message "${RED}服务未安装，请先运行安装${NC}"
        exit 1
    fi
    
    systemctl enable xmrig-cpulimit
    log_message "${GREEN}已启用开机自启动${NC}"
    systemctl status xmrig-cpulimit --no-pager -l
}

# 禁用服务
disable_service() {
    if [ ! -f "$SERVICE_FILE" ]; then
        log_message "${RED}服务未安装${NC}"
        exit 1
    fi
    
    systemctl disable xmrig-cpulimit
    log_message "${YELLOW}已禁用开机自启动${NC}"
}

# 服务启动（供systemd调用）
service_start() {
    local cpu_limit=${1:-$DEFAULT_CPU_LIMIT}
    
    # 等待xmrig启动
    log_message "等待xmrig启动..."
    local wait_time=0
    local max_wait=60
    
    while [ $wait_time -lt $max_wait ]; do
        if check_xmrig_running; then
            log_message "检测到xmrig正在运行，应用CPU限制..."
            start_cpulimit "$cpu_limit"
            return 0
        fi
        sleep 5
        wait_time=$((wait_time + 5))
        log_message "等待xmrig... (${wait_time}/${max_wait}秒)"
    done
    
    log_message "${RED}错误: 等待xmrig启动超时${NC}"
    return 1
}

# 服务停止（供systemd调用）
service_stop() {
    stop_cpulimit
}

# 服务重启（供systemd调用）
service_restart() {
    local cpu_limit=${1:-$DEFAULT_CPU_LIMIT}
    restart_cpulimit "$cpu_limit"
}

# 显示使用说明
show_usage() {
    echo -e "\n${BLUE}================== 使用说明 ==================${NC}"
    echo "脚本已安装到系统，可以使用以下命令："
    echo ""
    echo "1. 直接控制命令:"
    echo "   xmrig-cpulimit.sh start [CPU%]     # 启动CPU限制"
    echo "   xmrig-cpulimit.sh stop             # 停止CPU限制"
    echo "   xmrig-cpulimit.sh restart [CPU%]   # 重启CPU限制"
    echo "   xmrig-cpulimit.sh status           # 查看状态"
    echo ""
    echo "2. 服务管理命令:"
    echo "   systemctl start xmrig-cpulimit     # 启动服务"
    echo "   systemctl stop xmrig-cpulimit      # 停止服务"
    echo "   systemctl restart xmrig-cpulimit   # 重启服务"
    echo "   systemctl status xmrig-cpulimit    # 查看服务状态"
    echo "   journalctl -u xmrig-cpulimit -f    # 查看服务日志"
    echo ""
    echo "3. 系统管理命令:"
    echo "   xmrig-cpulimit.sh enable           # 启用开机自启"
    echo "   xmrig-cpulimit.sh disable          # 禁用开机自启"
    echo "   xmrig-cpulimit.sh uninstall        # 卸载脚本和服务"
    echo ""
    echo "4. 查看日志:"
    echo "   tail -f $LOG_FILE                  # 查看实时日志"
    echo "   cat $LOG_FILE                      # 查看完整日志"
    echo ""
    echo "5. 示例:"
    echo "   # 限制CPU为75%"
    echo "   xmrig-cpulimit.sh start 75"
    echo ""
    echo "   # 重启服务"
    echo "   systemctl restart xmrig-cpulimit"
    echo -e "${BLUE}============================================${NC}\n"
}

# 显示帮助
show_help() {
    echo -e "${BLUE}================== xmrig CPU限制控制脚本 ==================${NC}"
    echo "用于控制已安装xmrig的CPU使用率，支持系统服务管理"
    echo ""
    echo "安装和使用:"
    echo "  sudo $0 install [CPU%]      安装脚本和服务"
    echo "  $0 start [CPU%]             启动CPU限制"
    echo "  $0 stop                     停止CPU限制"
    echo "  $0 restart [CPU%]           重启CPU限制"
    echo "  $0 status                   查看状态"
    echo ""
    echo "服务管理:"
    echo "  $0 enable                   启用开机自启动"
    echo "  $0 disable                  禁用开机自启动"
    echo "  $0 uninstall                卸载脚本和服务"
    echo "  $0 help                     显示此帮助"
    echo ""
    echo "系统服务命令 (安装后可用):"
    echo "  systemctl start xmrig-cpulimit"
    echo "  systemctl stop xmrig-cpulimit"
    echo "  systemctl status xmrig-cpulimit"
    echo ""
    echo "注意:"
    echo "  1. 需要先安装cpulimit: sudo apt install cpulimit"
    echo "  2. xmrig需要已经在运行"
    echo "  3. 首次使用请运行安装命令"
    echo "  4. CPU限制值为1-100之间的整数"
    echo -e "${BLUE}==========================================================${NC}"
}

# 查看日志
view_log() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${BLUE}=== 最后100行日志 ===${NC}"
        tail -n 100 "$LOG_FILE"
        echo -e "${BLUE}=====================${NC}"
        echo "完整日志文件: $LOG_FILE"
        echo "日志大小: $(du -h "$LOG_FILE" | cut -f1)"
    else
        log_message "${YELLOW}日志文件不存在${NC}"
    fi
}

# 主函数
main() {
    # 创建必要的目录
    mkdir -p /var/run /var/log
    
    case "$1" in
        install)
            shift
            install_script "$@"
            ;;
        start)
            shift
            start_cpulimit "$@"
            ;;
        stop)
            stop_cpulimit
            ;;
        restart)
            shift
            restart_cpulimit "$@"
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
        uninstall)
            uninstall_script
            ;;
        service-start)
            shift
            service_start "$@"
            ;;
        service-stop)
            service_stop
            ;;
        service-restart)
            shift
            service_restart "$@"
            ;;
        log)
            view_log
            ;;
        help|--help|-h|"")
            show_help
            ;;
        *)
            # 如果第一个参数是数字，则作为CPU限制值
            if [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -le 100 ] && [ "$1" -ge 1 ]; then
                if [ "$2" == "start" ]; then
                    start_cpulimit "$1"
                elif [ "$2" == "restart" ]; then
                    restart_cpulimit "$1"
                else
                    log_message "${YELLOW}用法: $0 [CPU百分比] [start|restart]${NC}"
                    log_message "示例: $0 75 start"
                fi
            else
                log_message "${RED}未知命令: $1${NC}"
                show_help
                exit 1
            fi
            ;;
    esac
}

# 检查是否需要root权限
check_root_for_admin_commands() {
    local cmd="$1"
    local root_commands="install uninstall enable disable service-start service-stop service-restart"
    
    for root_cmd in $root_commands; do
        if [ "$cmd" == "$root_cmd" ]; then
            if [ "$EUID" -ne 0 ]; then 
                log_message "${RED}此命令需要root权限，请使用: sudo $0 $cmd${NC}"
                exit 1
            fi
        fi
    done
}

# 运行主函数
if [ $# -ge 1 ]; then
    check_root_for_admin_commands "$1"
fi

main "$@"
