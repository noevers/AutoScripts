#!/bin/bash

# 获取当前日期（格式：年月日，例如 20231015）
DATE=$(date +%Y%m%d)

# 根据日期生成一个范围在 30000-60000 之间的端口号
PORT=$(( (DATE % 30001) + 30000 ))

# 确保端口号在 30000-60000 之间
if [ $PORT -lt 30000 ] || [ $PORT -gt 60000 ]; then
    PORT=32669  # 如果超出范围，则使用默认值 30000
fi

# 更新 SSH 配置文件中的端口号
sed -i "s/^#\?Port .*/Port $PORT/" /etc/ssh/sshd_config

# 重启 SSH 服务以应用新的端口号
systemctl restart sshd

# 更新防火墙规则（假设使用 ufw）
ufw allow $PORT/tcp
ufw delete allow 22/tcp  # 删除旧的 SSH 端口规则（如果存在）

# 输出日志
echo "$(date): SSH 端口已更新为 $PORT" >> /var/log/ssh_port_update.log
