import os
import fnmatch
import paramiko
from scp import SCPClient
from threading import Thread, Event
from queue import Queue
import traceback  # 用于打印完整的堆栈跟踪
import time  # 用于重试间隔


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

def remote_mkdir(ssh, remote_dir):
    """
    在远程服务器上递归创建目录
    """
    try:
        stdin, stdout, stderr = ssh.exec_command(f"mkdir -p {remote_dir}")
        stderr_output = stderr.read().decode().strip()
        if stderr_output:
            print(f"Failed to create remote directory {remote_dir}: {stderr_output}")
            return False
        return True
    except Exception as e:
        print(f"Failed to create remote directory {remote_dir}: {e}")
        return False

def scp_transfer(file_path, remote_path, remote_host, remote_port, remote_user, remote_password, retries=3):
    """
    使用 SCP 传输文件到远程服务器，支持重试
    """
    for attempt in range(retries):
        try:
            # 检查本地文件是否存在
            if not os.path.exists(file_path):
                print(f"本地文件不存在: {file_path}")
                return
            if not os.access(file_path, os.R_OK):
                print(f"本地文件不可读: {file_path}")
                return

            # 创建 SSH 客户端
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            print(f"正在连接远程服务器 {remote_host}:{remote_port}...")
            ssh.connect(remote_host, port=remote_port, username=remote_user, password=remote_password, timeout=30)  # 设置超时时间
            print(f"成功连接到远程服务器 {remote_host}:{remote_port}！")

            # 检查远程文件是否存在
            if remote_file_exists(ssh, remote_path):
                print(f"文件已存在，跳过推送: {file_path} -> {remote_path}")
                ssh.close()
                return

            # 确保远程目录存在
            remote_dir = os.path.dirname(remote_path)
            if not remote_mkdir(ssh, remote_dir):
                print(f"无法创建远程目录: {remote_dir}")
                ssh.close()
                return

            # 创建 SCP 客户端
            print(f"开始推送文件: {file_path} -> {remote_path}")
            with SCPClient(ssh.get_transport(), socket_timeout=30) as scp:  # 设置 socket 超时时间
                scp.put(file_path, remote_path)
                print(f"文件推送完成: {file_path} -> {remote_path}")

            ssh.close()
            return  # 传输成功，退出函数
        except Exception as e:
            print(f"推送文件失败 (尝试 {attempt + 1}/{retries}): {file_path} -> {remote_path}")
            print(f"错误详情: {e}")
            print("堆栈跟踪:")
            traceback.print_exc()
            if attempt < retries - 1:
                print(f"等待 5 秒后重试...")
                time.sleep(5)  # 等待 5 秒后重试
            else:
                print(f"重试次数已达上限，放弃推送: {file_path} -> {remote_path}")

def worker(file_queue, remote_base_path, remote_host, remote_port, remote_user, remote_password, stop_event):
    """
    工作线程：从队列中获取文件并传输
    """
    while not stop_event.is_set():
        try:
            # 从队列中获取任务，设置超时时间
            local_file_path, remote_file_path = file_queue.get(timeout=5)  # 设置超时时间
            try:
                scp_transfer(local_file_path, remote_file_path, remote_host, remote_port, remote_user, remote_password)
            except Exception as e:
                print(f"推送文件失败: {local_file_path} -> {remote_file_path}, 错误: {e}")
            finally:
                file_queue.task_done()  # 确保任务完成
        except Exception as e:
            print(f"工作线程错误: {e}")
            break  # 退出线程

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
        print(f"无效路径: {local_path}")
        return

    # 创建并启动线程
    stop_event = Event()  # 用于通知线程退出
    thread_list = []
    for _ in range(threads):
        thread = Thread(target=worker, args=(file_queue, remote_base_path, remote_host, remote_port, remote_user, remote_password, stop_event), daemon=True)
        thread.start()
        thread_list.append(thread)

    # 等待所有任务完成
    file_queue.join()

    # 通知线程退出
    stop_event.set()

    # 等待所有线程退出
    for thread in thread_list:
        thread.join()

    print("所有文件推送完成！")

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
