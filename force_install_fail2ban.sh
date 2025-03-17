#!/bin/bash
# 功能：自动安装 UFW 防火墙和 Fail2Ban，联动封锁恶意 IP
# 适用系统：Debian 11
# 作者：运维专家

# 严格错误检查
set -euo pipefail

# 必须使用 root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[31m错误：必须使用 root 权限或 sudo 运行此脚本\033[0m" >&2
    exit 1
fi

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

# ------------------------- 安装 UFW 防火墙 -------------------------
install_ufw() {
    echo -e "${YELLOW}[1/4] 配置 UFW 防火墙...${NC}"

    
    apt-get remove --purge ufw
    apt-get autoremove
    apt-get clean

    # 安装 UFW
    if ! command -v ufw &> /dev/null; then
        echo "  安装 UFW 组件..."
        apt-get update -qq
        apt-get install -y ufw
    fi

    # 初始化防火墙规则
    echo "  设置默认规则..."
    ufw --force reset          # 重置已有规则
    ufw default deny incoming  # 默认阻止所有入站
    ufw default allow outgoing # 允许所有出站

    # 获取 SSH 端口
    SSHD_CONFIG="/etc/ssh/sshd_config"
    SSH_PORT=$(grep -E "^Port\s+" "$SSHD_CONFIG" | awk '{print $2}')
    if [[ -z "$SSH_PORT" ]]; then
        SSH_PORT=22
    fi

    # 允许 SSH 端口
    ufw allow "$SSH_PORT/tcp" comment 'SSH Port'

    # 拒绝 SSH 端口
    ufw deny out 22/tcp

    # 启用 UFW
    ufw --force enable
    echo -e "${GREEN}√ UFW 已激活，当前规则：${NC}"
    ufw status numbered | sed 's/^/  /'
}

# ------------------------- 安装 Fail2Ban -------------------------
install_fail2ban() {
    echo -e "${YELLOW}[2/4] 配置 Fail2Ban...${NC}"

    # 卸载旧版 Fail2Ban
    if dpkg -l | grep -q fail2ban; then
        echo "  卸载旧版 Fail2Ban..."
        systemctl stop fail2ban
        apt-get remove --purge -y fail2ban
        rm -rf /etc/fail2ban
    fi

    # 安装新版 Fail2Ban
    echo "  安装 Fail2Ban..."
    apt-get update -qq
    apt-get install -y fail2ban

    # 获取 SSH 端口
    SSHD_CONFIG="/etc/ssh/sshd_config"
    SSH_PORT=$(grep -E "^Port\s+" "$SSHD_CONFIG" | awk '{print $2}')
    if [[ -z "$SSH_PORT" ]]; then
        SSH_PORT=22
    fi

    # 生成 Fail2Ban 配置文件
    CONF_FILE="/etc/fail2ban/jail.local"
    echo "  生成 Fail2Ban 配置文件..."
    cat > "$CONF_FILE" << EOF
[DEFAULT]
# 使用 UFW 作为封禁工具
banaction = ufw
# 封禁时间：永久
bantime  = -1
# 允许最大失败次数
maxretry = 3
# 检测时间窗口：10 分钟
findtime = 180

[sshd]
enabled   = true
filter    = sshd
port      = $SSH_PORT
logpath   = %(sshd_log)s
maxretry  = 3
EOF

    # 重启 Fail2Ban 服务
    systemctl restart fail2ban
    echo -e "${GREEN}√ Fail2Ban 配置完成${NC}"
}

# ------------------------- 验证部署结果 -------------------------
validate_setup() {
    echo -e "${YELLOW}[3/4] 验证部署结果...${NC}"

    # 检查 UFW 状态
    if ! ufw status | grep -qw active; then
        echo -e "${RED}错误：UFW 未正常启动！${NC}" >&2
        exit 1
    fi

    # 检查 Fail2Ban 状态
    if ! fail2ban-client status sshd | grep -qw Active; then
        echo -e "${RED}错误：Fail2Ban 服务异常！${NC}" >&2
        exit 1
    fi

    echo -e "${GREEN}√ 所有服务运行正常${NC}"
}

# ------------------------- 输出部署信息 -------------------------
show_info() {
    echo -e "${YELLOW}[4/4] 部署完成！${NC}"
    echo -e "${GREEN}
    ███████╗ 部署成功！ ███████╗
    ╚═注意事项═╝
    1. 当前 SSH 端口: $SSH_PORT
    2. 封锁策略: 3 次失败后永久封禁
    3. 实时监控日志: tail -f /var/log/fail2ban.log
    4. 查看被封 IP: fail2ban-client status sshd
    ${NC}"
}

# 主执行流程
install_ufw
install_fail2ban
validate_setup
show_info
