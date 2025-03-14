#!/bin/bash

# 脚本名称: block_vodafone_hosts.sh
# 功能: 修改 /etc/hosts 文件，屏蔽指定的 Vodafone 域名

# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 用户运行此脚本！"
  exit 1
fi

# 目标域名列表
DOMAINS=(
  "vodafone.com"
  "vodafone.com.tr"
  "vodafone.com.eg"
  "vodafone.de"
  "vodafone.co.uk"
  "vodafone.com.it"
  "vodafone.com.au"
  "vodacom.co.za"
  "vodafone.co.tz"
  "vodacom.cd"
  "vodafone.nl"
  "vodafone.es"
  "vodafone.gr"
  "vodafone.ie"
  "vodafone.ro"
  "vodafone.pt"
  "vodafone.al"
  "vodafone.cz"
  "vodafone.co.ls"
)

# 备份 /etc/hosts 文件
echo "备份 /etc/hosts 文件..."
cp /etc/hosts /etc/hosts.bak

# 添加规则到 /etc/hosts 文件
echo "屏蔽指定的 Vodafone 域名..."
{
  echo "# Block Vodafone domains"
  for DOMAIN in "${DOMAINS[@]}"; do
    echo "127.0.0.1 $DOMAIN"
    echo "127.0.0.1 www.$DOMAIN"
  done
} >> /etc/hosts

# 提示完成
echo "已成功屏蔽指定的 Vodafone 域名！"
