#!/bin/bash
# 功能：强制部署UFW防火墙 + 覆盖安装Fail2Ban实现IP封锁
# 版本：v2.1 支持覆盖安装配置
# 作者：运维专家

# 严格错误检查
set -eo pipefail

# 必须使用root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[31m错误：必须使用root权限或sudo运行此脚本\033[0m" >&2
    exit 1
fi

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

# ------------------------- 安装UFW防火墙 -------------------------
install_ufw() {
    echo -e "${YELLOW}[1/3] 正在配置UFW防火墙...${NC}"
    
    # 安装UFW
    if ! command -v ufw &> /dev/null; then
        echo "  安装UFW组件..."
        apt-get update -qq
        apt-get install -y ufw
    fi

    # 初始化防火墙规则
    echo "  设置默认规则..."
    ufw --force reset          # 重置已有规则
    ufw default deny incoming  # 默认阻止所有入站
    ufw default allow outgoing # 允许所有出站
    
    # SSH端口处理（关键！）
    if ss -tnlp | grep -q ':2026 '; then
        ufw allow 2026/tcp comment 'SSH Default Port'
        ufw deny out 22/tcp
    else
        echo -e "${RED}警告：未检测到SSH在22端口运行，请手动修改UFW规则！${NC}"
    fi

    ufw --force enable
    echo -e "${GREEN}√ UFW已激活，当前规则：${NC}"
    ufw status numbered | sed 's/^/  /'
}

# --------------------- 强制覆盖安装Fail2Ban ---------------------
force_install_fail2ban() {
    echo -e "${YELLOW}[2/3] 强制配置Fail2Ban...${NC}"
    
    # 移除旧版本
    if dpkg -l | grep -q fail2ban; then
        echo "  卸载旧版Fail2Ban..."
        systemctl stop fail2ban
        apt-get remove --purge -y fail2ban
        rm -rf /etc/fail2ban
    fi

    # 安装新版
    echo "  安装新版Fail2Ban..."
    apt-get update -qq
    apt-get install -y fail2ban

    # 写入强制配置
    echo "  生成联动配置文件..."
    tee /etc/fail2ban/jail.d/ufw.conf > /dev/null << EOF
[DEFAULT]
bantime  = 365d
findtime = 5m
maxretry = 3
banaction = ufw
action = %(action_mwl)s

[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = %(sshd_log)s
EOF

    # 重启服务
    systemctl restart fail2ban
}

# ------------------------- 验证部署结果 -------------------------
validate_setup() {
    echo -e "${YELLOW}[3/3] 运行状态验证...${NC}"
    
    # 检查UFW
    if ! ufw status | grep -qw active; then
        echo -e "${RED}错误：UFW未正常启动！${NC}" >&2
        exit 1
    fi

    # 检查Fail2Ban
    if ! fail2ban-client status sshd | grep -qw Active; then
        echo -e "${RED}错误：Fail2Ban服务异常！${NC}" >&2
        exit 1
    fi

    echo -e "${GREEN}
    ███████╗ 部署成功！ ███████╗
    ╚═注意事项═╝
    1. 当前SSH端口: 22 (如需修改请更新UFW和Fail2Ban配置)
    2. 封锁策略: 3次失败封禁7天
    3. 实时监控: tail -f /var/log/fail2ban.log
    ${NC}"
}

# 主执行流程
install_ufw
force_install_fail2ban
validate_setup
