#!/bin/bash

# 磁盘格式化与UUID挂载脚本
# 用法: ./mount_disk.sh /dev/sdX /mount/path [filesystem]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 显示使用说明
usage() {
    echo "用法: $0 <磁盘设备> <挂载路径> [文件系统类型]"
    echo "示例:"
    echo "  $0 /dev/sdb /data"
    echo "  $0 /dev/sdb /data ext4"
    echo "  $0 /dev/sdb /data xfs"
    exit 1
}

# 检查参数
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    usage
fi

DISK="$1"
MOUNT_PATH="$2"
FS_TYPE="${3:-ext4}"

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用root权限运行此脚本${NC}"
    exit 1
fi

# 检查磁盘设备是否存在
if [ ! -b "$DISK" ]; then
    echo -e "${RED}错误: 磁盘设备 $DISK 不存在${NC}"
    exit 1
fi

# 检查挂载路径
if [ ! -d "$MOUNT_PATH" ]; then
    echo -e "${YELLOW}提示: 挂载路径 $MOUNT_PATH 不存在，正在创建...${NC}"
    mkdir -p "$MOUNT_PATH"
fi

# 检查磁盘是否已挂载
if mount | grep -q "$DISK"; then
    echo -e "${YELLOW}警告: 磁盘 $DISK 已挂载，正在卸载...${NC}"
    umount "$DISK" 2>/dev/null || true
fi

# 警告信息
echo -e "${YELLOW}警告: 这将格式化磁盘 $DISK 为 $FS_TYPE 文件系统${NC}"
echo -e "${YELLOW}磁盘上的所有数据都将被清除！${NC}"
read -p "是否继续? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "操作已取消"
    exit 0
fi

# 创建分区表（如果有需要）
echo -e "${GREEN}步骤1: 创建GPT分区表...${NC}"
parted "$DISK" --script mklabel gpt

# 创建主分区
echo -e "${GREEN}步骤2: 创建主分区...${NC}"
parted "$DISK" --script mkpart primary 0% 100%

# 获取分区路径
if [[ "$DISK" =~ /dev/nvme[0-9]+n[0-9]+$ ]] || [[ "$DISK" =~ /dev/mmcblk[0-9]+$ ]]; then
    PARTITION="${DISK}p1"
else
    PARTITION="${DISK}1"
fi

# 等待分区设备创建
echo "等待分区设备创建..."
sleep 2

# 检查分区是否创建成功
if [ ! -b "$PARTITION" ]; then
    echo -e "${RED}错误: 分区创建失败${NC}"
    exit 1
fi

# 格式化分区
echo -e "${GREEN}步骤3: 格式化分区为 $FS_TYPE ...${NC}"
case $FS_TYPE in
    ext4)
        mkfs.ext4 -F "$PARTITION"
        ;;
    xfs)
        mkfs.xfs -f "$PARTITION"
        ;;
    btrfs)
        mkfs.btrfs -f "$PARTITION"
        ;;
    *)
        echo -e "${RED}错误: 不支持的文件系统类型 $FS_TYPE${NC}"
        echo "支持的类型: ext4, xfs, btrfs"
        exit 1
        ;;
esac

# 获取UUID
echo -e "${GREEN}步骤4: 获取磁盘UUID...${NC}"
UUID=$(blkid -s UUID -o value "$PARTITION")

if [ -z "$UUID" ]; then
    echo -e "${RED}错误: 无法获取UUID${NC}"
    exit 1
fi

echo "磁盘UUID: $UUID"

# 备份fstab
echo -e "${GREEN}步骤5: 备份/etc/fstab...${NC}"
cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)

# 移除旧的挂载条目（如果有）
echo -e "${GREEN}步骤6: 更新/etc/fstab...${NC}"
# 移除旧的UUID挂载条目
sed -i "/$UUID/d" /etc/fstab 2>/dev/null || true
# 移除旧的挂载路径条目
sed -i "\|$MOUNT_PATH|d" /etc/fstab 2>/dev/null || true

# 添加新的挂载条目
FSTAB_ENTRY="UUID=$UUID $MOUNT_PATH $FS_TYPE defaults 0 0"
echo "$FSTAB_ENTRY" >> /etc/fstab

echo -e "${GREEN}fstab条目已添加:${NC}"
echo "$FSTAB_ENTRY"

# 挂载磁盘
echo -e "${GREEN}步骤7: 挂载磁盘...${NC}"
mount -a

# 验证挂载
if mount | grep -q "$MOUNT_PATH"; then
    echo -e "${GREEN}✓ 磁盘已成功挂载到 $MOUNT_PATH${NC}"
    
    # 显示磁盘信息
    echo -e "\n${GREEN}磁盘信息:${NC}"
    df -h "$MOUNT_PATH"
    
    # 显示UUID信息
    echo -e "\n${GREEN}UUID信息:${NC}"
    blkid "$PARTITION"
    
    # 设置权限（可选）
    read -p "是否设置目录权限为755? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        chmod 755 "$MOUNT_PATH"
        echo "权限已设置为755"
    fi
else
    echo -e "${RED}错误: 挂载失败${NC}"
    echo "请检查/etc/fstab配置"
    exit 1
fi

# 生成使用说明
echo -e "\n${GREEN}✓ 完成！磁盘已配置为开机自动挂载${NC}"
echo -e "UUID: $UUID"
echo -e "挂载点: $MOUNT_PATH"
echo -e "文件系统: $FS_TYPE"
