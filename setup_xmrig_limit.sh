#!/bin/bash
# 一键脚本：动态限制xmrig的CPU总利用率，并配置开机自启
# 用法: sudo ./setup_xmrig_limit.sh [总CPU利用率百分比]

set -e  # 遇到错误立即退出

# 1. 检查权限
if [ "$EUID" -ne 0 ]; then 
    echo "错误：请使用 sudo 或以 root 权限运行此脚本。"
    exit 1
fi

# 2. 处理参数
TARGET_UTILIZATION=${1:-50}
if ! [[ "$TARGET_UTILIZATION" =~ ^[0-9]+$ ]] || [ "$TARGET_UTILIZATION" -gt 100 ] || [ "$TARGET_UTILIZATION" -le 0 ]; then
    echo "错误：参数必须是1-100之间的整数，表示总CPU利用率百分比。"
    exit 1
fi

# 3. 定义常量
PROCESS_NAME="xmrig"
SERVICE_NAME="limit-xmrig"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SCRIPT_PATH="/usr/local/bin/limit_xmrig.sh" # 最终脚本存放位置

echo "============================================="
echo "目标：将进程 '${PROCESS_NAME}' 的总CPU利用率限制在 ${TARGET_UTILIZATION}%。"
echo "============================================="

# 4. 安装 cpulimit
echo "步骤 1/4: 检查并安装 cpulimit..."
if ! command -v cpulimit &> /dev/null; then
    apt-get update > /dev/null 2>&1 && apt-get install -y cpulimit > /dev/null 2>&1
    echo "cpulimit 安装完成。"
else
    echo "cpulimit 已安装。"
fi

# 5. 创建动态限制脚本到 /usr/local/bin
echo "步骤 2/4: 创建限制脚本..."
cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash
# 动态限制脚本，由 systemd 服务调用

TARGET_UTILIZATION="$1"
PROCESS_NAME="xmrig"

# 计算多核限制值
CPU_CORES=$(nproc)
CPULIMIT_LIMIT=$(( TARGET_UTILIZATION * CPU_CORES ))
MAX_LIMIT=$(( 100 * CPU_CORES ))
if [ $CPULIMIT_LIMIT -gt $MAX_LIMIT ]; then
    CPULIMIT_LIMIT=$MAX_LIMIT
fi

# 清理旧的 cpulimit 进程
OLD_PIDS=$(pidof cpulimit 2>/dev/null)
if [ ! -z "$OLD_PIDS" ]; then
    kill -9 $OLD_PIDS 2>/dev/null
fi

# 查找并限制目标进程
TARGET_PID=$(pgrep -f "$PROCESS_NAME" | head -n 1)
if [ ! -z "$TARGET_PID" ]; then
    # 后台启动 cpulimit，并避免生成僵尸进程
    nohup cpulimit -p "$TARGET_PID" -l "$CPULIMIT_LIMIT" -b -z > /dev/null 2>&1 &
    echo "限制已应用于 PID: $TARGET_PID (CPU核心: $CPU_CORES, 限制值: $CPULIMIT_LIMIT%)"
else
    echo "未找到进程 '$PROCESS_NAME'，将在1分钟后重试..."
    exit 1
fi
EOF

chmod +x "$SCRIPT_PATH"
echo "限制脚本已创建: $SCRIPT_PATH"

# 6. 创建并启用 systemd 服务
echo "步骤 3/4: 配置开机自启服务..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Limit CPU usage of xmrig process
After=network.target
# 如果 xmrig 是服务，可改为: After=xmrig.service
StartLimitBurst=5
StartLimitIntervalSec=30

[Service]
Type=simple
Restart=on-failure
RestartSec=60  # 进程退出后等待60秒重试
# 重要：将参数传递给脚本
ExecStart=$SCRIPT_PATH $TARGET_UTILIZATION
# 如果 xmrig 启动较慢，可以增加延迟
# ExecStartPre=/bin/sleep 30

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd 并启用服务
systemctl daemon-reload
systemctl enable "$SERVICE_NAME" > /dev/null 2>&1
echo "系统服务已创建: $SERVICE_FILE"

# 7. 立即启动服务并应用限制
echo "步骤 4/4: 启动服务并立即应用限制..."
systemctl restart "$SERVICE_NAME"
sleep 2  # 等待服务启动

# 检查服务状态
SERVICE_STATUS=$(systemctl is-active "$SERVICE_NAME")
if [ "$SERVICE_STATUS" = "active" ]; then
    echo "✅ 服务启动成功！"
    
    # 尝试检查限制是否应用
    CPULIMIT_PID=$(pidof cpulimit 2>/dev/null)
    if [ ! -z "$CPULIMIT_PID" ]; then
        echo "✅ cpulimit 进程正在运行 (PID: $CPULIMIT_PID)。"
    fi
    
    echo ""
    echo "============================================="
    echo "完成！配置摘要："
    echo "- CPU限制：总利用率 ${TARGET_UTILIZATION}%"
    echo "- 进程名：${PROCESS_NAME}"
    echo "- 服务名：${SERVICE_NAME}"
    echo "- 开机自启：已启用"
    echo "============================================="
    echo ""
    echo "管理命令："
    echo "  查看服务状态: sudo systemctl status ${SERVICE_NAME}"
    echo "  停止限制: sudo systemctl stop ${SERVICE_NAME}"
    echo "  临时禁用自启: sudo systemctl disable ${SERVICE_NAME}"
    echo "  查看日志: sudo journalctl -u ${SERVICE_NAME} -f"
else
    echo "⚠️  服务启动可能存在问题，请检查状态: sudo systemctl status ${SERVICE_NAME}"
fi
