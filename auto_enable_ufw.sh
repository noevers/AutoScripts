#!/bin/bash

# 脚本名称: setup_ufw_no_outbound_ssh.sh
# 功能: 安装 ufw 防火墙，并禁止所有出站 SSH 连接

# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 用户运行此脚本！"
  exit 1
fi

# 安装 ufw 防火墙
echo "正在安装 ufw 防火墙..."
apt update
apt install -y ufw

# 启用 ufw 防火墙
echo "启用 ufw 防火墙..."
ufw enable

# 设置默认策略：允许所有入站，拒绝所有出站
echo "设置默认策略：允许所有入站，拒绝所有出站..."
ufw default allow incoming

# 允许 SSH 入站（确保管理员可以远程连接）
echo "允许 SSH 入站（端口 22）..."
ufw allow 22/tcp

# 禁止所有出站 SSH 连接（端口 22）
echo "禁止所有出站 SSH 连接..."
ufw deny out 22/tcp

# 查看当前规则
echo "当前 ufw 规则如下："
ufw status verbose

# 提示完成
echo "ufw 防火墙配置完成！所有出站 SSH 连接已被禁止。"
