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
        ssh.connect(remote_host, port=remote_port, username=remote_user, password=remote_password)

        # 检查远程文件是否存在
        if remote_file_exists(ssh, remote_path):
            print(f"Skipped (already exists): {file_path} -> {remote_path}")
            ssh.close()
            return

        # 创建 SCP 客户端
        with SCPClient(ssh.get_transport()) as scp:
            scp.put(file_path, remote_path)
            print(f"Transferred: {file_path} -> {remote_path}")

        ssh.close()
    except Exception as e:
        print(f"Failed to transfer {file_path}: {e}")

def worker(file_queue, remote_base_path, remote_host, remote_port, remote_user, remote_password):
    """
    工作线程：从队列中获取文件并传输
    """
    while not file_queue.empty():
        local_file_path, remote_file_path = file_queue.get()
        scp_transfer(local_file_path, remote_file_path, remote_host, remote_port, remote_user, remote_password)
        file_queue.task_done()

def push_files(local_path, pattern, remote_host, remote_port, remote_user, remote_password, remote_base_path, threads):
    """
    推送文件或文件夹到远程服务器
    :param local_path: 本地路径（文件或文件夹）
    :param pattern: 文件名模糊匹配模式（例如 "*.txt"）
    :param remote_host: 远程服务器地址
    :param remote_port: 远程服务器端口
    :param remote_user: 远程服务器用户名
    :param remote_password: 远程服务器密码
    :param remote_base_path: 远程服务器目标路径
    :param threads: 并发线程数
    """
    if os.path.isfile(local_path):
        # 如果是文件，直接加入队列
        if fnmatch.fnmatch(os.path.basename(local_path), pattern):
            remote_file_path = os.path.join(remote_base_path, os.path.basename(local_path))
            file_queue.put((local_path, remote_file_path))
    elif os.path.isdir(local_path):
        # 如果是文件夹，遍历文件夹并匹配文件
        for root, _, files in os.walk(local_path):
            for file in files:
                if fnmatch.fnmatch(file, pattern):
                    local_file_path = os.path.join(root, file)
                    # 计算远程路径，保持目录结构
                    relative_path = os.path.relpath(local_file_path, local_path)
                    remote_file_path = os.path.join(remote_base_path, relative_path)
                    file_queue.put((local_file_path, remote_file_path))
    else:
        print(f"Invalid path: {local_path}")
        return

    # 创建并启动线程
    thread_list = []
    for _ in range(threads):
        thread = Thread(target=worker, args=(file_queue, remote_base_path, remote_host, remote_port, remote_user, remote_password))
        thread.start()
        thread_list.append(thread)

    # 等待所有任务完成
    file_queue.join()
    for thread in thread_list:
        thread.join()

    print("All files transferred!")

if __name__ == "__main__":
    # 文件队列
    file_queue = Queue()

    # 获取用户输入
    config = get_user_input()

    # 推送文件
    push_files(
        local_path=config["local_path"],
        pattern=config["pattern"],
        remote_host=config["remote_host"],
        remote_port=config["remote_port"],
        remote_user=config["remote_user"],
        remote_password=config["remote_password"],
        remote_base_path=config["remote_path"],
        threads=config["threads"],
    )
