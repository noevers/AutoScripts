#!/bin/bash

# 一键脚本：安装 pip3、paramiko 并运行 SCP 推送脚本

# 下载的 Python 脚本文件名
PYTHON_SCRIPT="scp_push_skip_existing.py"
# Python 脚本的下载链接（假设脚本托管在某个 URL）
SCRIPT_URL="https://raw.githubusercontent.com/noevers/AutoScripts/refs/heads/main/push_files.py"

# 检查是否安装了 Python3
if ! command -v python3 &> /dev/null; then
    echo "Python3 未安装，请先安装 Python3。"
    exit 1
fi

# 检查是否安装了 pip3
if ! command -v pip3 &> /dev/null; then
    echo "pip3 未安装，正在安装 pip3..."
    sudo apt-get update
    sudo apt-get install -y python3-pip
    if [ $? -ne 0 ]; then
        echo "安装 pip3 失败，请手动安装。"
        exit 1
    fi
    echo "pip3 安装成功！"
fi

# 安装 paramiko
echo "正在安装 paramiko..."
pip3 install paramiko

if [ $? -ne 0 ]; then
    echo "安装 paramiko 失败，请检查网络连接或手动安装。"
    exit 1
fi

# 下载 Python 脚本
echo "正在下载脚本..."
curl -o "$PYTHON_SCRIPT" "$SCRIPT_URL"

if [ $? -ne 0 ]; then
    echo "下载脚本失败，请检查 URL 或网络连接。"
    exit 1
fi

# 赋予脚本执行权限
chmod +x "$PYTHON_SCRIPT"

# 运行 Python 脚本
echo "正在运行脚本..."
python3 "$PYTHON_SCRIPT"
