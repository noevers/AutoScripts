#!/bin/bash
# setup_cpulimit_xmrig.sh - 通过进程名称限制xmrig的CPU使用率

set -e  # 遇到错误立即退出

DEFAULT_LIMIT=50  # 默认CPU总利用率限制为50%

# 显示使用说明
show_usage() {
    echo "用法: sudo $0 [CPU限制百分比]"
    echo "示例: $0 30        # 将xmrig的CPU总使用率限制在30%"
    echo "      $0           # 使用默认值50%"
    exit 1
}

# 参数检查
if [ $# -gt 1 ]; then
    show_usage
fi

if [ $# -eq 1 ]; then
    if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 1000 ]; then
        echo "错误: 请输入1-1000之间的整数作为CPU限制百分比。"
        show_usage
    fi
    LIMIT_PERCENT=$1
else
    LIMIT_PERCENT=$DEFAULT_LIMIT
fi

# 检查root权限
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 sudo 或以 root 用户运行此脚本。"
    exit 1
fi

echo "========================================"
echo "开始配置 xmrig CPU 限制 (总利用率: ${LIMIT_PERCENT}%)"
echo "========================================"

# 1. 安装 cpulimit
echo "步骤1: 安装cpulimit工具..."
if ! command -v cpulimit &> /dev/null; then
    apt-get update && apt-get install -y cpulimit
    echo "cpulimit 安装完成。"
else
    echo "cpulimit 已安装。"
fi

# 2. 创建监控脚本 (关键修改：使用 -e 参数按进程名限制)
echo "步骤2: 创建CPU限制监控脚本..."
cat > /usr/local/bin/limit_xmrig_cpu.sh << 'EOF'
#!/bin/bash
# 通过进程名监控并限制 xmrig 的CPU使用率

LIMIT_PERCENT=$1
LOG_FILE="/var/log/limit_xmrig_cpu.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 清理可能已存在的同名限制进程
pkill -f "cpulimit.*-e.*xmrig" 2>/dev/null && sleep 2

log_message "启动 xmrig CPU 限制监控 (总利用率限制: ${LIMIT_PERCENT}%)"

while true; do
    # 检查 xmrig 进程是否存在
    if pgrep -x xmrig > /dev/null; then
        # 检查是否已对“xmrig”这个名称启动了限制
        if ! pgrep -f "cpulimit.*-e.*xmrig" > /dev/null; then
            log_message "检测到 xmrig 进程，开始应用CPU限制..."

            # 动态计算多核CPU下的实际限制值
            CPU_COUNT=$(nproc 2>/dev/null || echo 1)
            ACTUAL_LIMIT=$((LIMIT_PERCENT * CPU_COUNT))
            
            log_message "系统CPU核心数: ${CPU_COUNT}, 计算后实际限制值: ${ACTUAL_LIMIT}%"

            # 核心命令：使用 -e 参数，通过进程名 xmrig 进行限制[citation:1][citation:3]
            cpulimit -e xmrig -l "$ACTUAL_LIMIT" -b >> "$LOG_FILE" 2>&1

            if [ $? -eq 0 ]; then
                log_message "CPU限制成功应用到程序: xmrig"
            else
                log_message "警告: 应用CPU限制失败"
            fi
        fi
    else
        log_message "未找到运行的 xmrig 进程。"
    fi
    # 等待10秒后再次检查
    sleep 10
done
EOF

# 3. 设置脚本权限
chmod +x /usr/local/bin/limit_xmrig_cpu.sh
echo "监控脚本创建完成: /usr/local/bin/limit_xmrig_cpu.sh"

# 4. 创建Systemd服务
echo "步骤3: 创建系统服务..."
cat > /etc/systemd/system/limit-xmrig.service << EOF
[Unit]
Description=Limit CPU usage for xmrig process by name
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/limit_xmrig_cpu.sh ${LIMIT_PERCENT}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 5. 创建日志文件
touch /var/log/limit_xmrig_cpu.log 2>/dev/null || true
chmod 644 /var/log/limit_xmrig_cpu.log 2>/dev/null || true

# 6. 启用并启动服务
echo "步骤4: 启用并启动服务..."
systemctl daemon-reload
systemctl enable limit-xmrig.service
systemctl start limit-xmrig.service

echo "========================================"
echo "配置完成!"
echo "========================================"
echo "CPU限制已设置为: ${LIMIT_PERCENT}% 总CPU利用率"
echo "限制方式: 通过进程名 'xmrig' 进行限制[citation:1]"
echo "监控服务已启用并启动。"
echo ""
echo "常用管理命令:"
echo "  查看服务状态: sudo systemctl status limit-xmrig.service"
echo "  查看实时日志: sudo journalctl -u limit-xmrig.service -f"
echo "  或查看日志文件: tail -f /var/log/limit_xmrig_cpu.log"
echo ""
echo "验证方法:"
echo "  1. 启动 xmrig 程序。"
echo "  2. 运行: top -p \$(pgrep xmrig)"
echo "  3. 观察 xmrig 的CPU使用率是否被限制在设定值附近。"
echo "  4. 检查限制进程: pgrep -af cpulimit"
echo "========================================"
