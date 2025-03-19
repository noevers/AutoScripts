# 依赖安装
#sudo apt update &&  apt install python3 python3-pip && pip3 install paramiko

import paramiko
import os
import threading
from getpass import getpass

# 远程服务器信息
REMOTE_HOST = input("请输入远程服务器地址(v6不需要[]): ")
REMOTE_PORT = int(input("请输入远程服务器端口 (默认 22): ") or 22)
REMOTE_USER = input("请输入远程服务器用户名: ")
REMOTE_PASSWORD = getpass("请输入远程服务器密码: ")
REMOTE_PATH = input("请输入远程目标路径: ")

# 本地文件夹路径
LOCAL_DIR = input("请输入本地文件夹路径: ")

# 线程数
THREADS = int(input("请输入线程数 (默认 4): ") or 4)

# 推送文件的函数
def scp_file(file_path):
    try:
        # 创建 SSH 客户端
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(REMOTE_HOST, port=REMOTE_PORT, username=REMOTE_USER, password=REMOTE_PASSWORD)

        # 远程路径
        remote_file_path = os.path.join(REMOTE_PATH, os.path.relpath(file_path, LOCAL_DIR))

        # 创建远程目录（如果不存在）
        remote_dir = os.path.dirname(remote_file_path)
        ssh.exec_command(f"mkdir -p {remote_dir}")

        # 使用 SCP 传输文件
        with ssh.open_sftp() as sftp:
            sftp.put(file_path, remote_file_path)
        print(f"推送成功：{file_path} -> {remote_file_path}")
    except Exception as e:
        print(f"推送失败：{file_path}，错误：{e}")
    finally:
        ssh.close()

# 获取文件夹下的所有文件
file_list = []
for root, _, files in os.walk(LOCAL_DIR):
    for file in files:
        file_list.append(os.path.join(root, file))

# 多线程推送
threads = []
for file_path in file_list:
    thread = threading.Thread(target=scp_file, args=(file_path,))
    threads.append(thread)
    thread.start()

    # 限制线程数
    if len(threads) >= THREADS:
        for thread in threads:
            thread.join()
        threads = []

# 等待剩余线程完成
for thread in threads:
    thread.join()

print("文件夹推送完成！")
