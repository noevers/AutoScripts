#!/bin/bash
# setup_cpulimit_xmrig.sh - 一键设置通过cpulimit限制xmrig的CPU使用率

set -e  # 遇到任何错误立即退出脚本

# 默认CPU限制率（总CPU利用率的百分比）
DEFAULT_LIMIT_PERCENT=50

# 使用说明
show_usage() {
    echo "用法: $0 [CPU限制百分比]"
    echo "示例: $0 50        # 将xmrig的CPU总使用率限制在50%"
    echo "      $0           # 使用默认值50%"
    echo ""
    echo "注意: 在多核CPU上，百分比基于总CPU容量计算（如4核CPU的100%代表4个核心满载）"
    exit 1
}

# 检查参数
if [ $# -gt 1 ]; then
    show_usage
fi

# 设置限制值
if [ $# -eq 1 ]; then
    # 检查是否为有效数字
    if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 1000 ]; then
        echo "错误: 限制百分比必须是1-1000之间的整数"
        show_usage
    fi
    LIMIT_PERCENT=$1
else
    LIMIT_PERCENT=$DEFAULT_LIMIT_PERCENT
fi

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
    echo "请使用sudo或以root用户运行此脚本"
    exit 1
fi

echo "========================================"
echo "开始配置xmrig CPU限制 (限制率: ${LIMIT_PERCENT}%)"
echo "========================================"

# 1. 安装cpulimit
echo "步骤1: 安装cpulimit工具..."
if ! command -v cpulimit &> /dev/null; then
    apt-get update && apt-get install -y cpulimit
    echo "cpulimit 安装完成"
else
    echo "cpulimit 已安装"
fi

# 2. 创建监控脚本
echo "步骤2: 创建CPU限制监控脚本..."
cat > /usr/local/bin/limit_xmrig_cpu.sh << 'EOF'
#!/bin/bash
# limit_xmrig_cpu.sh - 监控并限制xmrig的CPU使用率

# 获取传递的参数（CPU限制百分比）
LIMIT_PERCENT=$1
LOG_FILE="/var/log/limit_xmrig_cpu.log"

# 记录日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 检查是否已有限制进程在运行
if pgrep -f "cpulimit.*xmrig" > /dev/null; then
    log_message "发现已存在的cpulimit进程，正在停止..."
    pkill -f "cpulimit.*xmrig"
    sleep 2
fi

log_message "启动xmrig CPU限制监控 (限制率: ${LIMIT_PERCENT}%)"

# 循环监控
while true; do
    # 查找xmrig进程
    XMRIG_PID=$(pgrep -x xmrig)
    
    if [ -n "$XMRIG_PID" ]; then
        # 检查是否已对该PID进行限制
        if ! pgrep -f "cpulimit.*-p.*${XMRIG_PID}" > /dev/null; then
            log_message "发现xmrig进程(PID: ${XMRIG_PID})，应用CPU限制..."
            
            # 计算实际限制值（基于总CPU容量）
            CPU_COUNT=$(nproc)
            ACTUAL_LIMIT=$((LIMIT_PERCENT * CPU_COUNT))
            
            log_message "系统CPU核心数: ${CPU_COUNT}, 实际限制值: ${ACTUAL_LIMIT}%"
            
            # 启动cpulimit[citation:1]
            cpulimit -e xmrig -l "$ACTUAL_LIMIT" -b -z >> "$LOG_FILE" 2>&1[citation:1]
            
            if [ $? -eq 0 ]; then
                log_message "CPU限制成功应用到xmrig (PID: ${XMRIG_PID})"
            else
                log_message "警告: 应用CPU限制失败"
            fi
        fi
    else
        log_message "未找到运行的xmrig进程"
    fi
    
    # 等待一段时间再次检查
    sleep 10
done
EOF

# 3. 设置脚本权限
chmod +x /usr/local/bin/limit_xmrig_cpu.sh
echo "监控脚本创建完成: /usr/local/bin/limit_xmrig_cpu.sh"

# 4. 创建Systemd服务
echo "步骤3: 创建系统服务..."
cat > /etc/systemd/system/limit-xmrig-cpu.service << EOF
[Unit]
Description=Limit CPU usage for xmrig process
After=network.target multi-user.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/limit_xmrig_cpu.sh ${LIMIT_PERCENT}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 5. 创建日志文件
touch /var/log/limit_xmrig_cpu.log
chmod 644 /var/log/limit_xmrig_cpu.log

# 6. 启用并启动服务
echo "步骤4: 启用并启动服务..."
systemctl daemon-reload
systemctl enable limit-xmrig-cpu.service[citation:7]
systemctl start limit-xmrig-cpu.service

echo "========================================"
echo "配置完成!"
echo "========================================"
echo "CPU限制已设置为: ${LIMIT_PERCENT}% 总CPU利用率"
echo "监控服务已启用并启动"
echo ""
echo "管理命令:"
echo "  sudo systemctl status limit-xmrig-cpu.service  # 查看服务状态"
echo "  sudo systemctl stop limit-xmrig-cpu.service    # 停止服务"
echo "  sudo systemctl start limit-xmrig-cpu.service   # 启动服务"
echo "  sudo systemctl restart limit-xmrig-cpu.service # 重启服务"
echo ""
echo "查看日志:"
echo "  sudo journalctl -u limit-xmrig-cpu.service -f"
echo "  或查看 /var/log/limit_xmrig_cpu.log"
echo ""
echo "注意: 此限制将在系统重启后自动生效"
echo "========================================"
