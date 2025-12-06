#!/bin/bash
# 安全的一键安装脚本：为 xmrig 设置CPU限制监控服务
# 用法: sudo bash install_xmrig_limit.sh [总CPU利用率百分比]

set -e

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用 sudo 运行此脚本。"
    exit 1
fi

TARGET_UTILIZATION=${1:-50}
PROCESS_NAME="xmrig"
SERVICE_NAME="xmrig-cpu-limit"
MONITOR_SCRIPT="/usr/local/bin/xmrig_cpu_monitor.sh"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "正在为进程 '$PROCESS_NAME' 安装CPU限制监控服务 (目标: ${TARGET_UTILIZATION}%)..."

# 2. 安装 cpulimit
echo "安装 cpulimit..."
apt-get update > /dev/null 2>&1
apt-get install -y cpulimit > /dev/null 2>&1

# 3. 创建安全的监控脚本
echo "创建监控脚本..."
cat > "$MONITOR_SCRIPT" << EOF
#!/bin/bash
# 安全监控脚本：定期检查并限制 xmrig，绝不杀死它
TARGET_UTILILIZATION=$TARGET_UTILIZATION
PROCESS_NAME="$PROCESS_NAME"
CHECK_INTERVAL=10  # 检查间隔（秒）

echo "监控脚本启动。正在寻找进程 '\$PROCESS_NAME' 并限制其CPU总使用率为 \$TARGET_UTILILIZATION%..."

while true; do
    # 使用精确的 pgrep 模式匹配完整的进程命令，避免误杀
    XMRIG_PID=\$(pgrep -o -f "^[^ ]*${PROCESS_NAME}[^ ]*\$" 2>/dev/null | head -n 1)
    
    if [ -n "\$XMRIG_PID" ]; then
        # 计算多核限制值
        CPU_CORES=\$(nproc)
        CPULIMIT_LIMIT=\$(( TARGET_UTILILIZATION * CPU_CORES ))
        
        # 检查是否已为此 xmrig 进程设置了 cpulimit
        EXISTING_LIMIT_PID=\$(ps aux | grep "[c]pulimit -p \$XMRIG_PID" | awk '{print \$2}')
        
        if [ -n "\$EXISTING_LIMIT_PID" ]; then
            # 限制已存在，检查是否需要更新（例如CPU核心数变化或限制值变化）
            CURRENT_LIMIT=\$(ps -o args= -p \$EXISTING_LIMIT_PID | grep -o '\-l *[0-9]*' | awk '{print \$2}')
            if [ "\$CURRENT_LIMIT" != "\$CPULIMIT_LIMIT" ]; then
                echo "限制值变更 (\$CURRENT_LIMIT -> \$CPULIMIT_LIMIT)，更新中..."
                kill \$EXISTING_LIMIT_PID 2>/dev/null
                cpulimit -p \$XMRIG_PID -l \$CPULIMIT_LIMIT -b -z > /dev/null 2>&1
                echo "已为 PID \$XMRIG_PID 更新CPU限制：总利用率 \$TARGET_UTILILIZATION% (-\$l \$CPULIMIT_LIMIT)"
            fi
        else
            # 没有限制，应用新的限制
            cpulimit -p \$XMRIG_PID -l \$CPULIMIT_LIMIT -b -z > /dev/null 2>&1
            echo "已为 PID \$XMRIG_PID 应用CPU限制：总利用率 \$TARGET_UTILILIZATION% (-\$l \$CPULIMIT_LIMIT)"
        fi
    else
        # 如果 xmrig 不存在，确保清理遗留的孤立 cpulimit 进程
        # 使用更精确的模式匹配，只杀死限制此特定进程名的 cpulimit
        for CPULIMIT_PID in \$(pidof cpulimit 2>/dev/null); do
            if ps -p \$CPULIMIT_PID -o args= | grep -q "cpulimit.*-p.*[0-9]"; then
                # 这个 cpulimit 正在限制某个进程，检查该进程是否还存在
                LIMITED_PID=\$(ps -p \$CPULIMIT_PID -o args= | grep -o '\-p *[0-9]*' | awk '{print \$2}')
                if ! ps -p \$LIMITED_PID > /dev/null 2>&1; then
                    kill \$CPULIMIT_PID 2>/dev/null
                fi
            fi
        done
    fi
    
    sleep \$CHECK_INTERVAL
done
EOF

chmod +x "$MONITOR_SCRIPT"
echo "监控脚本已创建: $MONITOR_SCRIPT"

# 4. 创建并启用 systemd 服务
echo "配置 systemd 服务..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=CPU limit monitor for xmrig
After=network.target
# 不强依赖 xmrig，监控脚本会自己处理
Wants=network-online.target

[Service]
Type=simple
ExecStart=$MONITOR_SCRIPT
Restart=always
RestartSec=5
# 服务运行于低优先级
Nice=10
# 安全设置
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" > /dev/null 2>&1

# 5. 启动服务
echo "启动监控服务..."
systemctl restart "$SERVICE_NAME"
sleep 2

# 6. 验证安装
echo "验证安装..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "✅ 服务 '$SERVICE_NAME' 正在运行。"
    echo "✅ 安装完成！"
    echo ""
    echo "============================================="
    echo "配置摘要："
    echo "- 监控进程: $PROCESS_NAME"
    echo "- CPU总限制: $TARGET_UTILIZATION%"
    echo "- 监控脚本: $MONITOR_SCRIPT"
    echo "- 系统服务: $SERVICE_NAME"
    echo "- 开机自启: 已启用"
    echo "============================================="
    echo ""
    echo "管理命令："
    echo "  查看服务状态: sudo systemctl status $SERVICE_NAME"
    echo "  查看实时日志: sudo journalctl -u $SERVICE_NAME -f"
    echo "  停止服务: sudo systemctl stop $SERVICE_NAME"
    echo "  禁用开机自启: sudo systemctl disable $SERVICE_NAME"
else
    echo "⚠️  服务启动可能失败，请检查: sudo systemctl status $SERVICE_NAME"
fi
