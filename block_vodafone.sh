#!/bin/bash

# 脚本名称: block_vodafone.sh
# 功能: 安装 ufw 防火墙，并禁止访问 Vodafone 的所有站点

# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 用户运行此脚本！"
  exit 1
fi

# Vodafone 的 IP 地址范围（示例）
VODAFONE_IPS=(
  "123.45.67.0/24"
  "234.56.78.0/24"
  "139.7.147.0/24"
)

# 安装 ufw 防火墙
echo "正在安装 ufw 防火墙..."
apt update
apt install -y ufw

# 启用 ufw 防火墙
echo "启用 ufw 防火墙..."
ufw enable

# 禁止访问 Vodafone 的 IP 地址范围
for ip in "${VODAFONE_IPS[@]}"; do
  echo "禁止访问 IP 范围: $ip"
  ufw deny out to $ip
done

# 查看当前规则
echo "当前 ufw 规则如下："
ufw status verbose

# 提示完成
echo "ufw 防火墙配置完成！已禁止访问 Vodafone 的所有站点。"
