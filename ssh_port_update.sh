#!/bin/bash
# 功能：自动生成 SSH 端口，更新配置并更新 UFW 规则
# 适用系统：Debian 11
# 作者：运维专家

# 严格错误检查
set -euo pipefail

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

# ------------------------- 生成新端口 -------------------------
generate_port() {
    # 获取当前年月日
    CURRENT_DATE=$(date +%Y%m%d)

    # 使用哈希算法生成一个固定范围内的端口号
    PORT=$(( (CURRENT_DATE % 20000) + 30000 ))

    echo -e "${GREEN}√ 生成的新端口：$PORT${NC}"
    echo "$PORT"
}

# ------------------------- 更新 SSH 端口 -------------------------
update_ssh_port() {
    local OLD_PORT="$1"
    local NEW_PORT="$2"

    # 备份 SSH 配置文件
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # 更新 SSH 端口
    if grep -q "^Port" /etc/ssh/sshd_config; then
        sed -i "s/^Port.*/Port $NEW_PORT/" /etc/ssh/sshd_config
    else
        echo "Port $NEW_PORT" >> /etc/ssh/sshd_config
    fi

    echo -e "${GREEN}√ SSH 端口已更新为：$NEW_PORT${NC}"

    # 重启 SSH 服务
    systemctl restart ssh
    echo -e "${GREEN}√ SSH 服务已重启${NC}"
}

# ------------------------- 更新 UFW 规则 -------------------------
update_ufw_rules() {
    local OLD_PORT="$1"
    local NEW_PORT="$2"

    # 移除旧的 UFW 规则
    if ufw status | grep -q "$OLD_PORT/tcp"; then
        ufw delete allow "$OLD_PORT/tcp"
        echo -e "${GREEN}√ 已移除旧端口 $OLD_PORT 的 UFW 规则${NC}"
    else
        echo -e "${YELLOW}警告：未找到旧端口 $OLD_PORT 的 UFW 规则${NC}"
    fi

    # 添加新的 UFW 规则
    ufw allow "$NEW_PORT/tcp"
    echo -e "${GREEN}√ 已添加新端口 $NEW_PORT 的 UFW 规则${NC}"

    # 重启 UFW 服务
    ufw reload
    echo -e "${GREEN}√ UFW 服务已重启${NC}"
}

# ------------------------- 主逻辑 -------------------------
main() {
    # 获取当前 SSH 端口
    SSHD_CONFIG="/etc/ssh/sshd_config"
    OLD_PORT=$(grep -E "^Port\s+" "$SSHD_CONFIG" | awk '{print $2}' || echo "22")

    echo -e "${YELLOW}当前 SSH 端口：$OLD_PORT${NC}"

    # 生成新端口
    NEW_PORT=$(generate_port)

    # 更新 SSH 端口
    update_ssh_port "$OLD_PORT" "$NEW_PORT"

    # 更新 UFW 规则
    update_ufw_rules "$OLD_PORT" "$NEW_PORT"

    echo -e "${GREEN}
    ███████╗ 操作完成！ ███████╗
    ╚═注意事项═╝
    1. 旧 SSH 端口: $OLD_PORT
    2. 新 SSH 端口: $NEW_PORT
    3. 请使用新端口连接 SSH
    ${NC}"
}

# 执行主逻辑
main
