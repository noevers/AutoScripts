#!/bin/bash
# xmrig-cpu-limit-param.sh
# 通过参数配置xmrig CPU限制百分比

set -e

# 默认值
DEFAULT_PERCENT=50
PROCESS_NAME="xmrig"
VERSION="2.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示帮助
show_help() {
    echo -e "${GREEN}xmrig CPU限制配置工具 v${VERSION}${NC}"
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -p, --percent N   限制百分比 (0-100)，默认: ${DEFAULT_PERCENT}"
    echo "  -n, --name NAME   进程名，默认: ${PROCESS_NAME}"
    echo "  -c, --cores N     手动指定CPU核心数 (默认自动检测)"
    echo "  -m, --mode MODE   限制模式:"
    echo "                     auto    - 自动根据核心数计算 (默认)"
    echo "                     total   - 限制总CPU百分比"
    echo "                     percore - 每个核心单独限制"
    echo "  -i, --install     安装模式 (默认)"
    echo "  -u, --uninstall   卸载模式"
    echo "  -s, --status      查看状态"
    echo "  -r, --restart     重启服务"
    echo "  -h, --help        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -p 30              # 限制xmrig到总CPU的30%"
    echo "  $0 -p 50 -n myminer   # 限制'myminer'进程到50%"
    echo "  $0 -p 25 -m percore   # 每个核心限制到25%"
    echo "  $0 -c 8 -p 50         # 指定8核心，限制到50%"
    echo "  $0 --uninstall        # 卸载限制"
    echo ""
}

# 参数解析
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--percent)
                LIMIT_PERCENT="$2"
                shift 2
                ;;
            -n|--name)
                PROCESS_NAME="$2"
                shift 2
                ;;
            -c|--cores)
                MANUAL_CORES="$2"
                shift 2
                ;;
            -m|--mode)
                LIMIT_MODE="$2"
                shift 2
                ;;
            -i|--install)
                ACTION="install"
                shift
                ;;
            -u|--uninstall)
                ACTION="uninstall"
                shift
                ;;
            -s|--status)
                ACTION="status"
                shift
                ;;
            -r|--restart)
                ACTION="restart"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}未知参数: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

# 检查参数有效性
validate_params() {
    # 设置默认值
    LIMIT_PERCENT=${LIMIT_PERCENT:-$DEFAULT_PERCENT}
    LIMIT_MODE=${LIMIT_MODE:-"auto"}
    ACTION=${ACTION:-"install"}
    
    # 验证百分比
    if ! [[ "$LIMIT_PERCENT" =~ ^[0-9]+$ ]] || [ "$LIMIT_PERCENT" -lt 0 ] || [ "$LIMIT_PERCENT" -gt 100 ]; then
        echo -e "${RED}错误: 百分比必须在0-100之间${NC}"
        exit 1
    fi
    
    # 验证进程名
    if [ -z "$PROCESS_NAME" ]; then
        echo -e "${RED}错误: 进程名不能为空${NC}"
        exit 1
    fi
    
    # 验证模式
    case $LIMIT_MODE in
        auto|total|percore)
            # 有效模式
            ;;
        *)
            echo -e "${RED}错误: 无效模式 '$LIMIT_MODE'，必须是 auto, total 或 percore${NC}"
            exit 1
            ;;
    esac
}

# 显示配置信息
show_config() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}       CPU限制配置信息${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "目标进程: $PROCESS_NAME"
    echo "限制百分比: ${LIMIT_PERCENT}%"
    echo "限制模式: $LIMIT_MODE"
    
    if [ -n "$MANUAL_CORES" ]; then
        echo "手动指定核心: $MANUAL_CORES"
        CPU_CORES=$MANUAL_CORES
    else
        # 检测CPU核心数
        if command -v nproc &> /dev/null; then
            CPU_CORES=$(nproc)
        else
            CPU_CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
        fi
        echo "检测到CPU核心: $CPU_CORES"
    fi
    
    # 计算实际限制
    case $LIMIT_MODE in
        auto)
            # 自动模式：基于核心数计算总限制
            if [ "$LIMIT_PERCENT" -le 100 ]; then
                TOTAL_LIMIT=$((CPU_CORES * LIMIT_PERCENT))
                echo "实际限制: ${TOTAL_LIMIT}% (${LIMIT_PERCENT}% × ${CPU_CORES}核心)"
            else
                TOTAL_LIMIT=$LIMIT_PERCENT
                echo "实际限制: ${TOTAL_LIMIT}% (直接使用)"
            fi
            ;;
        total)
            # 总百分比模式
            TOTAL_LIMIT=$LIMIT_PERCENT
            echo "实际限制: ${TOTAL_LIMIT}% (总CPU)"
            ;;
        percore)
            # 每核心百分比模式
            TOTAL_LIMIT=$((CPU_CORES * LIMIT_PERCENT))
            echo "实际限制: ${TOTAL_LIMIT}% (每核心${LIMIT_PERCENT}%)"
            ;;
    esac
    
    echo -e "${BLUE}========================================${NC}"
}

# 安装cpulimit
install_cpulimit() {
    if ! command -v cpulimit &> /dev/null; then
        echo -e "${YELLOW}安装cpulimit...${NC}"
        apt update >/dev/null 2>&1
        apt install -y cpulimit >/dev/null 2>&1
        echo -e "${GREEN}✓ cpulimit安装完成${NC}"
    else
        echo -e "${GREEN}✓ cpulimit已安装${NC}"
    fi
}

# 生成服务名（避免特殊字符）
generate_service_name() {
    SAFE_NAME=$(echo "$PROCESS_NAME" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
    echo "cpulimit-${SAFE_NAME}-${LIMIT_PERCENT}"
}

# 创建限制服务
create_limit_service() {
    SERVICE_NAME=$(generate_service_name)
    
    echo -e "${YELLOW}创建服务: $SERVICE_NAME.service${NC}"
    
    # 计算实际限制值
    case $LIMIT_MODE in
        auto)
            if [ "$LIMIT_PERCENT" -le 100 ]; then
                FINAL_LIMIT=$((CPU_CORES * LIMIT_PERCENT))
            else
                FINAL_LIMIT=$LIMIT_PERCENT
            fi
            ;;
        total)
            FINAL_LIMIT=$LIMIT_PERCENT
            ;;
        percore)
            FINAL_LIMIT=$((CPU_CORES * LIMIT_PERCENT))
            ;;
    esac
    
    # 创建服务文件
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=CPU Limit ${LIMIT_PERCENT}% for ${PROCESS_NAME}
After=network.target
Wants=${PROCESS_NAME}.service
After=${PROCESS_NAME}.service

[Service]
Type=simple
# 等待目标进程启动
ExecStartPre=/bin/bash -c '
    echo "等待 ${PROCESS_NAME} 进程启动..."
    MAX_WAIT=60
    WAITED=0
    while [ \$WAITED -lt \$MAX_WAIT ]; do
        if pgrep -x "${PROCESS_NAME}" >/dev/null; then
            PID=\$(pgrep -x "${PROCESS_NAME}" | head -1)
            echo "找到 ${PROCESS_NAME} (PID: \$PID)"
            exit 0
        fi
        sleep 1
        WAITED=\$((WAITED + 1))
    done
    echo "错误: 等待超时，未找到 ${PROCESS_NAME}"
    exit 1
'
# 应用CPU限制
ExecStart=/bin/bash -c '
    PID=\$(pgrep -x "${PROCESS_NAME}" | head -1)
    if [ -n "\$PID" ]; then
        echo "应用CPU限制: ${PROCESS_NAME}(PID:\$PID) -> ${FINAL_LIMIT}%"
        cpulimit -p \$PID -l ${FINAL_LIMIT} -z
    else
        echo "错误: 未找到 ${PROCESS_NAME} 进程"
        exit 1
    fi
'
Restart=always
RestartSec=10
RestartPreventExitStatus=1
SuccessExitStatus=143

# 日志配置
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

    # 创建监控服务（处理进程重启）
    create_monitor_service
}

# 创建监控服务
create_monitor_service() {
    MONITOR_SERVICE="${SERVICE_NAME}-monitor"
    
    # 创建监控脚本
    cat > /usr/local/bin/${MONITOR_SERVICE}.sh << 'MONITOR_EOF'
#!/bin/bash
# 监控脚本：自动重新应用CPU限制

PROCESS_NAME="'"${PROCESS_NAME}"'"
FINAL_LIMIT='"${FINAL_LIMIT}"'
SERVICE_NAME="'"${SERVICE_NAME}"'"

echo "开始监控进程: \$PROCESS_NAME"
echo "目标限制: \$FINAL_LIMIT%"

while true; do
    # 查找所有匹配的进程
    PIDS=\$(pgrep -x "\$PROCESS_NAME")
    
    if [ -n "\$PIDS" ]; then
        for PID in \$PIDS; do
            # 检查是否已经有限制
            if ! ps aux | grep -v grep | grep -q "cpulimit.*-p \$PID"; then
                echo "\$(date): 发现新进程 \$PID，应用CPU限制: \$FINAL_LIMIT%"
                
                # 杀掉可能存在的旧限制进程
                pkill -f "cpulimit.*-p \$PID" 2>/dev/null
                
                # 应用新的限制
                cpulimit -p \$PID -l \$FINAL_LIMIT -b >/dev/null 2>&1
                
                # 记录到系统日志
                logger -t "\$SERVICE_NAME" "限制 \$PROCESS_NAME(PID:\$PID) 到 \${FINAL_LIMIT}% CPU"
            fi
        done
    else
        echo "\$(date): 未找到 \$PROCESS_NAME 进程"
    fi
    
    sleep 5
done
MONITOR_EOF

    chmod +x /usr/local/bin/${MONITOR_SERVICE}.sh
    
    # 创建监控服务文件
    cat > /etc/systemd/system/${MONITOR_SERVICE}.service << EOF
[Unit]
Description=CPU Limit Monitor for ${PROCESS_NAME}
After=network.target
PartOf=${SERVICE_NAME}.service

[Service]
Type=simple
ExecStart=/usr/local/bin/${MONITOR_SERVICE}.sh
Restart=always
RestartSec=5

[Install]
WantedBy=${SERVICE_NAME}.service
EOF
}

# 创建管理脚本
create_management_scripts() {
    SERVICE_NAME=$(generate_service_name)
    
    # 创建状态查看脚本
    cat > /usr/local/bin/cpulimit-manager << 'MANAGER_EOF'
#!/bin/bash
# CPU限制管理器

ACTION=\${1:-"status"}
TARGET=\${2:-""}

case \$ACTION in
    status)
        echo "=== CPU限制服务状态 ==="
        systemctl list-units --type=service --all | grep cpulimit
        echo ""
        echo "=== 运行的cpulimit进程 ==="
        ps aux | grep -v grep | grep cpulimit
        echo ""
        echo "=== 被限制的进程 ==="
        for pid in \$(pgrep -f "cpulimit.*-p"); do
            LIMITED_PID=\$(ps aux | grep "cpulimit.*-p" | grep -oP "(?<=-p )\d+")
            if [ -n "\$LIMITED_PID" ]; then
                PROCESS=\$(ps -p \$LIMITED_PID -o comm= 2>/dev/null)
                LIMIT=\$(ps aux | grep "cpulimit.*-p \$LIMITED_PID" | grep -oP "(?<=-l )\d+")
                echo "PID: \$LIMITED_PID, 进程: \$PROCESS, 限制: \${LIMIT}%"
            fi
        done
        ;;
        
    list)
        echo "=== 已配置的CPU限制服务 ==="
        ls /etc/systemd/system/cpulimit-*.service 2>/dev/null | while read service; do
            SERVICE_NAME=\$(basename \$service .service)
            echo "服务: \$SERVICE_NAME"
            systemctl is-active \$SERVICE_NAME >/dev/null 2>&1 && STATUS="运行中" || STATUS="已停止"
            echo "状态: \$STATUS"
            echo ""
        done
        ;;
        
    stop)
        if [ -n "\$TARGET" ]; then
            systemctl stop \$TARGET 2>/dev/null
            echo "已停止服务: \$TARGET"
        else
            echo "停止所有cpulimit服务..."
            systemctl list-units --type=service | grep cpulimit | awk '{print \$1}' | while read service; do
                systemctl stop \$service 2>/dev/null
            done
            pkill cpulimit 2>/dev/null
            echo "已停止所有CPU限制"
        fi
        ;;
        
    start)
        if [ -n "\$TARGET" ]; then
            systemctl start \$TARGET 2>/dev/null
            echo "已启动服务: \$TARGET"
        else
            echo "请指定要启动的服务名"
        fi
        ;;
        
    restart)
        if [ -n "\$TARGET" ]; then
            systemctl restart \$TARGET 2>/dev/null
            echo "已重启服务: \$TARGET"
        else
            echo "请指定要重启的服务名"
        fi
        ;;
        
    remove)
        if [ -n "\$TARGET" ]; then
            systemctl stop \$TARGET 2>/dev/null
            systemctl disable \$TARGET 2>/dev/null
            rm -f /etc/systemd/system/\$TARGET.service
            rm -f /etc/systemd/system/\$TARGET-monitor.service 2>/dev/null
            rm -f /usr/local/bin/\$TARGET*.sh 2>/dev/null
            systemctl daemon-reload
            echo "已移除服务: \$TARGET"
        else
            echo "请指定要移除的服务名"
        fi
        ;;
        
    adjust)
        if [ -n "\$TARGET" ]; then
            NEW_LIMIT=\${3}
            if ! [[ "\$NEW_LIMIT" =~ ^[0-9]+$ ]]; then
                echo "错误: 请输入有效的百分比数字"
                exit 1
            fi
            
            # 获取当前配置
            SERVICE_FILE="/etc/systemd/system/\$TARGET.service"
            if [ -f "\$SERVICE_FILE" ]; then
                # 更新服务文件中的限制值（简化版，实际需要更复杂的解析）
                echo "调整限制功能需要手动编辑服务文件"
                echo "请使用: sudo nano \$SERVICE_FILE"
            else
                echo "服务文件不存在: \$TARGET"
            fi
        else
            echo "用法: cpulimit-manager adjust <服务名> <新百分比>"
        fi
        ;;
        
    *)
        echo "用法: cpulimit-manager [命令] [服务名]"
        echo "命令:"
        echo "  status     - 查看状态 (默认)"
        echo "  list       - 列出所有服务"
        echo "  stop       - 停止服务"
        echo "  start      - 启动服务"
        echo "  restart    - 重启服务"
        echo "  remove     - 移除服务"
        echo "  adjust     - 调整限制百分比"
        ;;
esac
MANAGER_EOF

    chmod +x /usr/local/bin/cpulimit-manager
}

# 安装模式
install() {
    echo -e "${GREEN}开始安装CPU限制...${NC}"
    
    # 显示配置信息
    show_config
    
    # 安装依赖
    install_cpulimit
    
    # 创建服务
    create_limit_service
    
    # 创建管理脚本
    create_management_scripts
    
    # 启用并启动服务
    SERVICE_NAME=$(generate_service_name)
    MONITOR_SERVICE="${SERVICE_NAME}-monitor"
    
    echo -e "${YELLOW}启用服务...${NC}"
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}.service
    systemctl enable ${MONITOR_SERVICE}.service
    systemctl start ${SERVICE_NAME}.service
    systemctl start ${MONITOR_SERVICE}.service
    
    # 验证安装
    echo -e "${YELLOW}验证安装...${NC}"
    sleep 2
    
    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        echo -e "${GREEN}✓ 主服务运行正常${NC}"
    else
        echo -e "${YELLOW}⚠ 主服务状态异常${NC}"
        systemctl status ${SERVICE_NAME}.service --no-pager -l | tail -10
    fi
    
    if systemctl is-active --quiet ${MONITOR_SERVICE}.service; then
        echo -e "${GREEN}✓ 监控服务运行正常${NC}"
    else
        echo -e "${YELLOW}⚠ 监控服务状态异常${NC}"
        systemctl status ${MONITOR_SERVICE}.service --no-pager -l | tail -10
    fi
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}      安装完成！${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "服务名称: ${SERVICE_NAME}.service"
    echo "监控服务: ${MONITOR_SERVICE}.service"
    echo "目标进程: $PROCESS_NAME"
    echo "限制设置: ${FINAL_LIMIT}% CPU"
    echo ""
    echo "管理命令:"
    echo "  cpulimit-manager                  # 查看状态"
    echo "  cpulimit-manager list             # 列出所有限制"
    echo "  cpulimit-manager stop             # 停止所有限制"
    echo "  systemctl status ${SERVICE_NAME}  # 查看服务状态"
    echo "  journalctl -u ${SERVICE_NAME} -f  # 查看实时日志"
    echo ""
    echo "如需调整限制，请使用:"
    echo "  $0 --uninstall       # 先卸载"
    echo "  $0 -p <新百分比>     # 重新配置"
    echo -e "${BLUE}========================================${NC}"
}

# 卸载模式
uninstall() {
    echo -e "${YELLOW}卸载CPU限制...${NC}"
    
    if [ -n "$PROCESS_NAME" ] && [ "$PROCESS_NAME" != "xmrig" ]; then
        # 卸载特定进程的限制
        SERVICE_NAME="cpulimit-$(echo "$PROCESS_NAME" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')"
        echo "查找服务: ${SERVICE_NAME}*"
        
        # 查找并停止相关服务
        systemctl list-units --type=service --all | grep "${SERVICE_NAME}" | awk '{print $1}' | while read service; do
            echo "停止服务: $service"
            systemctl stop $service 2>/dev/null
            systemctl disable $service 2>/dev/null
        done
        
        # 删除服务文件
        rm -f /etc/systemd/system/${SERVICE_NAME}*.service 2>/dev/null
        rm -f /usr/local/bin/${SERVICE_NAME}*.sh 2>/dev/null
    else
        # 卸载所有cpulimit服务
        echo "卸载所有cpulimit限制..."
        
        # 停止所有cpulimit服务
        systemctl list-units --type=service --all | grep cpulimit | awk '{print $1}' | while read service; do
            echo "停止服务: $service"
            systemctl stop $service 2>/dev/null
            systemctl disable $service 2>/dev/null
        done
        
        # 删除所有相关文件
        rm -f /etc/systemd/system/cpulimit-*.service 2>/dev/null
        rm -f /usr/local/bin/cpulimit-*.sh 2>/dev/null
        rm -f /usr/local/bin/cpulimit-manager 2>/dev/null
        
        # 杀掉所有cpulimit进程
        pkill cpulimit 2>/dev/null
    fi
    
    systemctl daemon-reload
    echo -e "${GREEN}✓ 卸载完成${NC}"
}

# 状态查看
status() {
    echo -e "${BLUE}=== CPU限制状态 ===${NC}"
    
    # 服务状态
    echo -e "${YELLOW}服务状态:${NC}"
    systemctl list-units --type=service --all | grep -E "(cpulimit|limit)" || echo "未找到相关服务"
    
    echo ""
    
    # 进程状态
    echo -e "${YELLOW}cpulimit进程:${NC}"
    ps aux | grep -v grep | grep cpulimit || echo "未找到cpulimit进程"
    
    echo ""
    
    # 被限制的进程
    echo -e "${YELLOW}被限制的进程:${NC}"
    found=0
    for pid in $(pgrep cpulimit 2>/dev/null); do
        # 提取cpulimit命令的参数
        CMDLINE=$(ps -p $pid -o args= 2>/dev/null)
        if [[ $CMDLINE =~ -p[[:space:]]+([0-9]+)[[:space:]]+-l[[:space:]]+([0-9]+) ]]; then
            LIMITED_PID=${BASH_REMATCH[1]}
            LIMIT_PERCENT=${BASH_REMATCH[2]}
            PROCESS_NAME=$(ps -p $LIMITED_PID -o comm= 2>/dev/null)
            CPU_USAGE=$(ps -p $LIMITED_PID -o %cpu= 2>/dev/null)
            echo "进程: $PROCESS_NAME (PID: $LIMITED_PID)"
            echo "  限制: $LIMIT_PERCENT%"
            echo "  当前CPU: ${CPU_USAGE}%"
            echo ""
            found=1
        fi
    done
    
    if [ $found -eq 0 ]; then
        echo "未找到被限制的进程"
    fi
    
    # 系统CPU信息
    echo -e "${YELLOW}系统CPU信息:${NC}"
    echo "核心数: $(nproc 2>/dev/null || echo '未知')"
    echo "总负载: $(uptime | awk -F'load average:' '{print $2}')"
}

# 重启服务
restart() {
    if [ -n "$PROCESS_NAME" ] && [ "$PROCESS_NAME" != "xmrig" ]; then
        SERVICE_NAME="cpulimit-$(echo "$PROCESS_NAME" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')"
        echo "重启服务: ${SERVICE_NAME}"
        systemctl restart ${SERVICE_NAME}.service 2>/dev/null || echo "服务不存在或已停止"
    else
        echo "重启所有cpulimit服务..."
        systemctl list-units --type=service --all | grep cpulimit | awk '{print $1}' | while read service; do
            echo "重启: $service"
            systemctl restart $service 2>/dev/null
        done
    fi
    echo -e "${GREEN}✓ 重启完成${NC}"
}

# 主函数
main() {
    # 解析参数
    parse_args "$@"
    
    # 验证参数
    validate_params
    
    # 执行相应操作
    case $ACTION in
        install)
            install
            ;;
        uninstall)
            uninstall
            ;;
        status)
            status
            ;;
        restart)
            restart
            ;;
        *)
            echo -e "${RED}未知操作: $ACTION${NC}"
            exit 1
            ;;
    esac
}

# 脚本入口
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

main "$@"
