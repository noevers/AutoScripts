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
