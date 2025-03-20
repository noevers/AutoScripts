import os
import fnmatch
import paramiko
from scp import SCPClient
from threading import Thread
from queue import Queue

def get_user_input():
    """
    通过交互方式获取用户输入
    """
    local_path = input("请输入本地文件或文件夹路径: ").strip()
    pattern = input("请输入文件名匹配模式（例如 *.txt，默认全部文件）: ").strip() or "*"
    remote_host = input("请输入远程服务器地址: ").strip()
    remote_port = int(input("请输入远程服务器端口（默认 22）: ").strip() or 22)
    remote_user = input("请输入远程服务器用户名: ").strip()
    remote_password = input("请输入远程服务器密码: ").strip()
    remote_path = input("请输入远程服务器目标路径: ").strip()
    threads = int(input("请输入并发线程数（默认 4）: ").strip() or 4)

    return {
        "local_path": local_path,
        "pattern": pattern,
        "remote_host": remote_host,
        "remote_port": remote_port,
        "remote_user": remote_user,
        "remote_password": remote_password,
        "remote_path": remote_path,
        "threads": threads,
    }

def remote_file_exists(ssh, remote_file_path):
    """
    检查远程服务器上是否存在目标文件
    """
    try:
        stdin, stdout, stderr = ssh.exec_command(f"test -e {remote_file_path} && echo exists")
        return "exists" in stdout.read().decode().strip()
    except Exception as e:
        print(f"Failed to check remote file {remote_file_path}: {e}")
        return False

def scp_transfer(file_path, remote_path, remote_host, remote_port, remote_user, remote_password):
    """
    使用 SCP 传输文件到远程服务器
    """
    try:
        # 创建 SSH 客户端
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(remote_host,
