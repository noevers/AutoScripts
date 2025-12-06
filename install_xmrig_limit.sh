#!/bin/bash
# ============================================================================
# xmrig CPU限制器 (cpulimit方案)
# 完整功能：安装、配置、管理、卸载
# 用法: 
#   安装/配置: sudo ./xmrig_cpulimit_manager.sh install [CPU百分比]
#   状态检查: sudo ./xmrig_cpulimit_manager.sh status
#   停止限制: sudo ./xmrig_cpulimit_manager.sh stop
#   完全卸载: sudo ./xmrig_cpulimit_manager.sh uninstall
# 示例: sudo ./xmrig_cpulimit_manager.sh install 50
# ============================================================================

set -e

# 配置区域
PROCESS_PATTERN="/root/c3pool/xmrig.*"  # xmrig进程查找模式
SERVICE_NAME="xmrig-cpulimit-daemon"           # systemd服务名称
MONITOR_SCRIPT="/usr/local/bin/xmrig_cpulimit_monitor.sh"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LOG_FILE="/var/log/xmrig-cpulimit.log"
CPU_PERCENT="${2:-50}"  # 默认50%

# 颜色定义
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# 检查root权限
check_root() {
    [ "$EUID" -ne 0 ] && { error "请使用sudo运行"; exit 1; }
}

# 安装依赖
install_deps() {
    info "检查系统依赖..."
    if ! command -v cpulimit &>/dev/null; then
        info "安装 cpulimit..."
        apt-get update >/dev/null 2>&1 && apt-get install -y cpulimit >/dev/null 2>&1
    fi
    if ! command -v jq &>/dev/null; then
        apt-get install -y jq >/dev/null 2>&1
    fi
}

# 查找xmrig进程
find_xmrig() {
    # 方法1: 精确命令行匹配
    local pid=$(ps aux | grep -E "$PROCESS_PATTERN" | grep -v grep | awk '{print $2}' | head -n1)
    
    # 方法2: 如果未找到，尝试网络连接特征
    if [ -z "$pid" ]; then
        local net_pid=$(ss -tunp 2>/dev/null | grep -E ':(3333|443|5555|14444|80)' | 
                       grep -o 'pid=[0-9]*' | cut -d= -f2 | head -n1)
        [ -n "$net_pid" ] && ps -p "$net_pid" >/dev/null 2>&1 && pid="$net_pid"
    fi
    
    echo "$pid"
}

# 创建监控脚本
create_monitor_script() {
    cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
# xmrig cpulimit监控脚本

TARGET_PERCENT="$1"
PROCESS_PATTERN="$2"
LOG_FILE="$3"
CHECK_INTERVAL=15
FAIL_COUNT=0
MAX_FAILS=10

# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 清理旧cpulimit进程
cleanup_old_limit() {
    for cp_pid in $(pidof cpulimit 2>/dev/null); do
        # 检查这个cpulimit是否在限制我们的目标进程
        local target_pid=$(ps -p "$cp_pid" -o args= | grep -o '\-p[[:space:]]*[0-9]*' | awk '{print $2}')
        if [ -n "$target_pid" ] && ! ps -p "$target_pid" >/dev/null 2>&1; then
            kill "$cp_pid" 2>/dev/null && log "清理孤立cpulimit进程: $cp_pid"
        fi
    done
}

log "=== 监控脚本启动 ==="
log "目标CPU限制: ${TARGET_PERCENT}%"

while true; do
    # 查找xmrig进程
    XMRIG_PID=$(ps aux | grep -E "$PROCESS_PATTERN" | grep -v grep | awk '{print $2}' | head -n1)
    
    if [ -n "$XMRIG_PID" ]; then
        FAIL_COUNT=0
        CPU_CORES=$(nproc)
        CPULIMIT_VALUE=$((TARGET_PERCENT * CPU_CORES))
        
        # 检查是否已有限制
        EXISTING_LIMIT_PID=""
        for cp_pid in $(pidof cpulimit 2>/dev/null); do
            if ps -p "$cp_pid" -o args= | grep -q "\-p[[:space:]]*$XMRIG_PID"; then
                EXISTING_LIMIT_PID="$cp_pid"
                break
            fi
        done
        
        if [ -z "$EXISTING_LIMIT_PID" ]; then
            # 应用新限制
            cleanup_old_limit
            if cpulimit -p "$XMRIG_PID" -l "$CPULIMIT_VALUE" -b -z >> "$LOG_FILE" 2>&1; then
                log "已应用限制: PID=$XMRIG_PID, 核心数=$CPU_CORES, 限制值=$CPULIMIT_VALUE"
            else
                log "应用限制失败: PID=$XMRIG_PID"
            fi
        fi
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log "未找到xmrig进程 (失败计数: $FAIL_COUNT/$MAX_FAILS)"
        
        if [ "$FAIL_COUNT" -ge "$MAX_FAILS" ]; then
            log "多次未找到xmrig进程，清理后退出"
            cleanup_old_limit
            exit 1
        fi
        
        # xmrig不存在时清理可能孤立的cpulimit
        cleanup_old_limit
    fi
    
    sleep "$CHECK_INTERVAL"
done
EOF
    
    chmod +x "$MONITOR_SCRIPT"
    info "监控脚本已创建: $MONITOR_SCRIPT"
}

# 创建systemd服务
create_systemd_service() {
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=CPU Limit Daemon for xmrig (cpulimit)
After=network.target
Wants=network-online.target
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=simple
Environment="TARGET_PERCENT=$CPU_PERCENT"
Environment="PROCESS_PATTERN=$PROCESS_PATTERN"
Environment="LOG_FILE=$LOG_FILE"
ExecStart=$MONITOR_SCRIPT \$TARGET_PERCENT "\$PROCESS_PATTERN" \$LOG_FILE
Restart=on-failure
RestartSec=30
StandardOutput=journal
StandardError=journal

# 安全限制
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=$LOG_FILE /tmp

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    info "systemd服务已创建: $SERVICE_FILE"
}

# 安装主函数
install() {
    check_root
    info "开始安装xmrig CPU限制器 (cpulimit方案)..."
    
    install_deps
    create_monitor_script
    create_systemd_service
    
    # 启动服务
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    systemctl restart "$SERVICE_NAME"
    
    sleep 2
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        info "✅ 安装完成！"
        info "========================================"
        info "配置摘要:"
        info "  - 目标CPU限制: ${CPU_PERCENT}%"
        info "  - 监控进程: ${PROCESS_PATTERN}"
        info "  - 服务名称: ${SERVICE_NAME}"
        info "  - 日志文件: ${LOG_FILE}"
        info "========================================"
        info "管理命令:"
        info "  查看状态: sudo systemctl status ${SERVICE_NAME}"
        info "  查看日志: sudo journalctl -u ${SERVICE_NAME} -f"
        info "  停止限制: sudo systemctl stop ${SERVICE_NAME}"
        info "========================================"
    else
        error "服务启动失败，请检查日志: sudo journalctl -u ${SERVICE_NAME}"
        exit 1
    fi
}

# 状态检查
status() {
    echo "=== xmrig CPU限制器状态 (cpulimit方案) ==="
    
    # 服务状态
    if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
        echo -e "服务状态: ${GREEN}运行中${NC}"
        systemctl status "$SERVICE_NAME" --no-pager -l | head -20
    else
        echo -e "服务状态: ${RED}未运行${NC}"
    fi
    
    echo ""
    
    # xmrig进程状态
    XMRIG_PID=$(find_xmrig)
    if [ -n "$XMRIG_PID" ]; then
        echo -e "xmrig进程: ${GREEN}运行中 (PID: $XMRIG_PID)${NC}"
        
        # CPU使用率
        CPU_USAGE=$(ps -p "$XMRIG_PID" -o %cpu --no-headers | awk '{sum+=$1} END {print sum}')
        echo "当前CPU使用率: ${CPU_USAGE}%"
        
        # 检查cpulimit限制
        for cp_pid in $(pidof cpulimit 2>/dev/null); do
            if ps -p "$cp_pid" -o args= | grep -q "\-p[[:space:]]*$XMRIG_PID"; then
                LIMIT_VALUE=$(ps -p "$cp_pid" -o args= | grep -o '\-l[[:space:]]*[0-9]*' | awk '{print $2}')
                CPU_CORES=$(nproc)
                TARGET_PERCENT=$((LIMIT_VALUE / CPU_CORES))
                echo -e "cpulimit限制: ${GREEN}已应用 (-l $LIMIT_VALUE ≈ 总$TARGET_PERCENT%)${NC}"
                break
            fi
        done
    else
        echo -e "xmrig进程: ${RED}未找到${NC}"
    fi
    
    echo ""
    echo "最近日志:"
    tail -10 "$LOG_FILE" 2>/dev/null || echo "日志文件不存在"
}

# 停止限制
stop() {
    info "停止CPU限制..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl disable "$SERVICE_NAME" 2>/dev/null
    
    # 清理所有cpulimit进程
    for pid in $(pidof cpulimit 2>/dev/null); do
        kill "$pid" 2>/dev/null
    done
    
    info "限制已停止，xmrig将恢复全速运行"
}

# 完全卸载
uninstall() {
    info "开始卸载..."
    stop
    
    # 删除文件
    rm -f "$MONITOR_SCRIPT" "$SERVICE_FILE" "$LOG_FILE"
    systemctl daemon-reload
    
    info "✅ 卸载完成"
}

# 主程序
case "$1" in
    "install")
        install
        ;;
    "status")
        status
        ;;
    "stop")
        stop
        ;;
    "uninstall")
        uninstall
        ;;
    *)
        echo "使用方法: $0 {install [百分比]|status|stop|uninstall}"
        echo "示例:"
        echo "  $0 install 50     # 安装并限制为50%CPU"
        echo "  $0 status         # 查看状态"
        echo "  $0 stop           # 停止限制"
        echo "  $0 uninstall      # 完全卸载"
        exit 1
        ;;
esac
