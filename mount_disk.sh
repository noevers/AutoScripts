#!/bin/bash

# 磁盘格式化与UUID挂载脚本
# 用法: ./mount_disk.sh /dev/sdX /mount/path [filesystem]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查并安装必要的工具
check_dependencies() {
    local missing=()
    
    # 检查parted
    if ! command -v parted &> /dev/null; then
        missing+=("parted")
    fi
    
    # 检查mkfs工具
    if ! command -v mkfs.ext4 &> /dev/null; then
        missing+=("e2fsprogs")
    fi
    
    if ! command -v blkid &> /dev/null; then
        missing+=("util-linux")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}缺少必要的工具: ${missing[*]}${NC}"
        echo -e "${BLUE}正在安装必要工具...${NC}"
        
        apt-get update
        
        for pkg in "${missing[@]}"; do
            case $pkg in
                "parted")
                    echo "安装 parted..."
                    apt-get install -y parted
                    ;;
                "e2fsprogs")
                    echo "安装 e2fsprogs..."
                    apt-get install -y e2fsprogs
                    ;;
                "util-linux")
                    echo "安装 util-linux..."
                    apt-get install -y util-linux
                    ;;
            esac
        done
        
        # 检查xfs工具（如果需要）
        if [[ "$FS_TYPE" == "xfs" ]] && ! command -v mkfs.xfs &> /dev/null; then
            echo "安装 xfsprogs..."
            apt-get install -y xfsprogs
        fi
        
        # 检查btrfs工具（如果需要）
        if [[ "$FS_TYPE" == "btrfs" ]] && ! command -v mkfs.btrfs &> /dev/null; then
            echo "安装 btrfs-progs..."
            apt-get install -y btrfs-progs
        fi
        
        echo -e "${GREEN}工具安装完成${NC}"
    fi
}

# 显示使用说明
usage() {
    echo "磁盘格式化与UUID挂载脚本"
    echo "用法: $0 <磁盘设备> <挂载路径> [文件系统类型]"
    echo ""
    echo "参数:"
    echo "  磁盘设备     如: /dev/sdb, /dev/nvme0n1"
    echo "  挂载路径     如: /data, /mnt/storage"
    echo "  文件系统类型 可选: ext4 (默认), xfs, btrfs"
    echo ""
    echo "示例:"
    echo "  $0 /dev/sdb /data"
    echo "  $0 /dev/sdb /data ext4"
    echo "  $0 /dev/nvme0n1 /fast-storage xfs"
    echo "  $0 /dev/sdc /backup btrfs"
    echo ""
    echo "注意: 此操作会格式化磁盘，所有数据将被清除！"
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
    echo "请使用: sudo $0 $*"
    exit 1
fi

# 检查文件系统类型是否支持
case $FS_TYPE in
    ext4|xfs|btrfs)
        # 文件系统类型有效
        ;;
    *)
        echo -e "${RED}错误: 不支持的文件系统类型 '$FS_TYPE'${NC}"
        echo "支持的类型: ext4, xfs, btrfs"
        exit 1
        ;;
esac

# 检查依赖
check_dependencies

# 检查磁盘设备是否存在
if [ ! -b "$DISK" ]; then
    echo -e "${RED}错误: 磁盘设备 $DISK 不存在${NC}"
    echo "可用磁盘:"
    lsblk -d -o NAME,SIZE,TYPE,RO | grep -E '^(sd|nvme|vd|xvd|mmcblk)'
    exit 1
fi

# 检查是否是完整的磁盘设备（不是分区）
if [[ "$DISK" =~ [0-9]$ ]] && [[ ! "$DISK" =~ nvme[0-9]+n[0-9]+$ ]]; then
    echo -e "${RED}错误: 请指定磁盘设备，而不是分区${NC}"
    echo "请使用磁盘设备，如: /dev/sdb 而不是 /dev/sdb1"
    echo "当前磁盘:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
    exit 1
fi

# 检查磁盘是否正在使用
if mount | grep -q "^$DISK"; then
    echo -e "${RED}错误: 磁盘 $DISK 已被挂载${NC}"
    mount | grep "^$DISK"
    exit 1
fi

# 检查挂载路径
if [ -d "$MOUNT_PATH" ] && [ "$(ls -A $MOUNT_PATH 2>/dev/null)" ]; then
    echo -e "${YELLOW}警告: 挂载路径 $MOUNT_PATH 不为空${NC}"
    read -p "是否继续? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "操作已取消"
        exit 0
    fi
elif [ ! -d "$MOUNT_PATH" ]; then
    echo -e "${BLUE}创建挂载目录: $MOUNT_PATH${NC}"
    mkdir -p "$MOUNT_PATH"
fi

# 显示磁盘信息
echo -e "${BLUE}当前磁盘信息:${NC}"
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT,UUID "$DISK"

# 警告信息
echo -e "\n${RED}⚠  ⚠  ⚠  警告: 这将格式化磁盘 $DISK 为 $FS_TYPE 文件系统${NC}"
echo -e "${RED}磁盘上的所有数据都将被永久清除！${NC}\n"
read -p "是否继续? (输入 'YES' 确认): " -r
if [[ ! "$REPLY" == "YES" ]]; then
    echo "操作已取消"
    exit 0
fi

# 创建分区表
echo -e "\n${GREEN}步骤1: 创建GPT分区表...${NC}"
parted "$DISK" --script mklabel gpt

# 创建主分区
echo -e "${GREEN}步骤2: 创建主分区...${NC}"
parted "$DISK" --script mkpart primary 0% 100%

# 获取分区路径
if [[ "$DISK" =~ /dev/nvme[0-9]+n[0-9]+$ ]]; then
    PARTITION="${DISK}p1"
elif [[ "$DISK" =~ /dev/mmcblk[0-9]+$ ]]; then
    PARTITION="${DISK}p1"
elif [[ "$DISK" =~ /dev/loop[0-9]+$ ]]; then
    PARTITION="${DISK}p1"
else
    PARTITION="${DISK}1"
fi

# 等待分区设备创建
echo -e "${BLUE}等待分区设备创建...${NC}"
sleep 3
attempt=1
while [ ! -b "$PARTITION" ] && [ $attempt -le 5 ]; do
    echo "等待分区设备... ($attempt/5)"
    sleep 2
    attempt=$((attempt + 1))
done

# 检查分区是否创建成功
if [ ! -b "$PARTITION" ]; then
    echo -e "${RED}错误: 分区创建失败，请手动检查${NC}"
    echo "尝试重新扫描磁盘..."
    partprobe "$DISK"
    sleep 2
    if [ ! -b "$PARTITION" ]; then
        echo -e "${RED}错误: 无法创建分区，请手动检查磁盘${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}分区创建成功: $PARTITION${NC}"

# 格式化分区
echo -e "${GREEN}步骤3: 格式化分区为 $FS_TYPE ...${NC}"
case $FS_TYPE in
    ext4)
        echo "使用 mkfs.ext4 格式化..."
        mkfs.ext4 -F -m 0 "$PARTITION"
        ;;
    xfs)
        echo "使用 mkfs.xfs 格式化..."
        mkfs.xfs -f "$PARTITION"
        ;;
    btrfs)
        echo "使用 mkfs.btrfs 格式化..."
        mkfs.btrfs -f "$PARTITION"
        ;;
esac

# 获取UUID
echo -e "${GREEN}步骤4: 获取磁盘UUID...${NC}"
UUID=$(blkid -s UUID -o value "$PARTITION")

if [ -z "$UUID" ]; then
    echo -e "${RED}错误: 无法获取UUID${NC}"
    echo "尝试重新扫描..."
    partprobe "$DISK"
    sleep 2
    UUID=$(blkid -s UUID -o value "$PARTITION")
    
    if [ -z "$UUID" ]; then
        echo -e "${RED}错误: 仍然无法获取UUID，尝试使用lsblk...${NC}"
        UUID=$(lsblk -o UUID "$PARTITION" | tail -1)
    fi
fi

if [ -z "$UUID" ]; then
    echo -e "${RED}错误: 无法获取UUID，使用设备名称代替${NC}"
    UUID_PATH="$PARTITION"
else
    echo -e "${GREEN}磁盘UUID: $UUID${NC}"
    UUID_PATH="UUID=$UUID"
fi

# 备份fstab
echo -e "${GREEN}步骤5: 备份/etc/fstab...${NC}"
FSTAB_BACKUP="/etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
cp /etc/fstab "$FSTAB_BACKUP"
echo "fstab已备份到: $FSTAB_BACKUP"

# 更新fstab
echo -e "${GREEN}步骤6: 更新/etc/fstab...${NC}"

# 移除旧的挂载条目
if [ -n "$UUID" ]; then
    # 移除相同UUID的条目
    grep -v "UUID=$UUID" /etc/fstab > /tmp/fstab.tmp && mv /tmp/fstab.tmp /etc/fstab
fi

# 移除相同挂载路径的条目
grep -v " $MOUNT_PATH " /etc/fstab > /tmp/fstab.tmp && mv /tmp/fstab.tmp /etc/fstab

# 添加新的挂载条目
FSTAB_ENTRY="$UUID_PATH $MOUNT_PATH $FS_TYPE defaults 0 0"
echo "$FSTAB_ENTRY" >> /etc/fstab

echo -e "${GREEN}fstab条目已添加:${NC}"
echo "$FSTAB_ENTRY"

# 测试fstab配置
echo -e "${BLUE}测试fstab配置...${NC}"
if mount -a 2>&1 | grep -q "错误\|error\|fail"; then
    echo -e "${RED}错误: fstab配置测试失败${NC}"
    mount -a 2>&1 | grep -v "already mounted"
    echo -e "${YELLOW}正在恢复fstab备份...${NC}"
    cp "$FSTAB_BACKUP" /etc/fstab
    exit 1
fi

# 挂载磁盘
echo -e "${GREEN}步骤7: 挂载磁盘...${NC}"
mount "$MOUNT_PATH"

# 验证挂载
if mountpoint -q "$MOUNT_PATH"; then
    echo -e "${GREEN}✓ 磁盘已成功挂载到 $MOUNT_PATH${NC}"
    
    # 显示磁盘信息
    echo -e "\n${GREEN}磁盘信息:${NC}"
    df -h "$MOUNT_PATH"
    
    # 显示UUID信息
    echo -e "\n${GREEN}UUID信息:${NC}"
    blkid "$PARTITION"
    
    # 设置权限
    echo -e "\n${BLUE}设置目录权限...${NC}"
    chmod 755 "$MOUNT_PATH"
    echo "权限已设置为755"
    
    # 生成示例文件
    echo "挂载测试文件" > "$MOUNT_PATH/.mount_test.txt"
    echo "测试文件创建成功"
    
else
    echo -e "${RED}错误: 挂载失败${NC}"
    echo "请检查/etc/fstab配置:"
    tail -1 /etc/fstab
    exit 1
fi

# 完成信息
echo -e "\n${GREEN}✓ 完成！磁盘已成功配置${NC}"
echo "========================================="
echo "磁盘:        $DISK"
echo "分区:        $PARTITION"
echo "UUID:        $UUID"
echo "挂载点:      $MOUNT_PATH"
echo "文件系统:    $FS_TYPE"
echo "fstab备份:   $FSTAB_BACKUP"
echo "========================================="
echo -e "${YELLOW}提示: 重启后会自动挂载${NC}"

# 显示最终状态
echo -e "\n${BLUE}最终状态:${NC}"
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT,UUID "$DISK"
