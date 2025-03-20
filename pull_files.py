import os
import fnmatch
import paramiko
from scp import SCPClient
from threading import Thread, Event
from queue import Queue
import traceback
import time

def get_user_input():
    """
    通过交互方式获取用户输入
    """
    remote_path = input("请输入远程文件或文件夹路径: ").strip()
    pattern = input("请输入文件名匹配模式（例如 *.txt，默认全部文件）: ").strip() or "*"
    remote_host = input("请输入远程服务器地址: ").strip()
    remote_port = int(input("请输入远程服务器端口（默认 22）: ").strip() or 22)
    remote_user = input("请输入远程服务器用户名: ").strip()
    remote_password = input("请输入远程服务器密码: ").strip()
    local_path = input("请输入本地目标路径: ").strip()
    threads = int(input("请输入并发线程数（默认 4）: ").strip() or 4)

    return {
        "remote_path": remote_path,
        "pattern": pattern,
        "remote_host": remote_host,
        "remote_port": remote_port,
        "remote_user": remote_user,
        "remote_password": remote_password,
        "local_path": local_path,
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

def scp_pull(remote_path, local_path, remote_host, remote_port, remote_user, remote_password, retries=3):
    """
    使用 SCP 从远程服务器拉取文件，支持重试
    """
    for attempt in range(retries):
        try:
            # 创建 SSH 客户端
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            print(f"正在连接远程服务器 {remote_host}:{remote_port}...")
            ssh.connect(remote_host, port=remote_port, username=remote_user, password=remote_password, timeout=60)  # 设置超时时间
            print(f"成功连接到远程服务器 {remote_host}:{remote_port}！")

            # 检查远程文件是否存在
            if not remote_file_exists(ssh, remote_path):
                print(f"远程文件不存在: {remote_path}")
                ssh.close()
                return

            # 确保本地目录存在
            local_dir = os.path.dirname(local_path)
            os.makedirs(local_dir, exist_ok=True)

            # 创建 SCP 客户端
            print(f"开始拉取文件: {remote_path} -> {local_path}")
            with SCPClient(ssh.get_transport(), socket_timeout=60) as scp:  # 设置 socket 超时时间
                scp.get(remote_path, local_path)
                print(f"文件拉取完成: {remote_path} -> {local_path}")

            ssh.close()
            return  # 拉取成功，退出函数
        except Exception as e:
            print(f"拉取文件失败 (尝试 {attempt + 1}/{retries}): {remote_path} -> {local_path}")
            print(f"错误详情: {e}")
            print("堆栈跟踪:")
            traceback.print_exc()
            if attempt < retries - 1:
                print(f"等待 5 秒后重试...")
                time.sleep(5)  # 等待 5 秒后重试
            else:
                print(f"重试次数已达上限，放弃拉取: {remote_path} -> {local_path}")

def worker(file_queue, local_base_path, remote_host, remote_port, remote_user, remote_password, stop_event):
    """
    工作线程：从队列中获取文件并拉取
    """
    while not stop_event.is_set():
        try:
            # 从队列中获取任务，设置超时时间
            remote_file_path, local_file_path = file_queue.get(timeout=5)  # 设置超时时间
            try:
                scp_pull(remote_file_path, local_file_path, remote_host, remote_port, remote_user, remote_password)
            except Exception as e:
                print(f"拉取文件失败: {remote_file_path} -> {local_file_path}, 错误: {e}")
            finally:
                file_queue.task_done()  # 确保任务完成
        except Exception as e:
            print(f"工作线程错误: {e}")
            break  # 退出线程

def pull_files(remote_path, pattern, remote_host, remote_port, remote_user, remote_password, local_base_path, threads):
    """
    从远程服务器拉取文件或文件夹
    :param remote_path: 远程路径（文件或文件夹）
    :param pattern: 文件名匹配模式（例如 "*.txt"）
    :param remote_host: 远程服务器地址
    :param remote_port: 远程服务器端口
    :param remote_user: 远程服务器用户名
    :param remote_password: 远程服务器密码
    :param local_base_path: 本地目标路径
    :param threads: 并发线程数
    """
    # 创建 SSH 客户端以获取远程文件列表
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(remote_host, port=remote_port, username=remote_user, password=remote_password)

    if not remote_file_exists(ssh, remote_path):
        print(f"远程路径不存在: {remote_path}")
        ssh.close()
        return

    # 如果是文件，直接加入队列
    stdin, stdout, stderr = ssh.exec_command(f"test -f {remote_path} && echo file")
    if "file" in stdout.read().decode().strip():
        if fnmatch.fnmatch(os.path.basename(remote_path), pattern):
            local_file_path = os.path.join(local_base_path, os.path.basename(remote_path))
            file_queue.put((remote_path, local_file_path))
    else:
        # 如果是文件夹，遍历文件夹并匹配文件
        stdin, stdout, stderr = ssh.exec_command(f"find {remote_path} -type f")
        for line in stdout:
            remote_file_path = line.strip()
            if fnmatch.fnmatch(os.path.basename(remote_file_path), pattern):
                relative_path = os.path.relpath(remote_file_path, remote_path)
                local_file_path = os.path.join(local_base_path, relative_path)
                file_queue.put((remote_file_path, local_file_path))

    ssh.close()

    # 创建并启动线程
    stop_event = Event()  # 用于通知线程退出
    thread_list = []
    for _ in range(threads):
        thread = Thread(target=worker, args=(file_queue, local_base_path, remote_host, remote_port, remote_user, remote_password, stop_event), daemon=True)
        thread.start()
        thread_list.append(thread)

    # 等待所有任务完成
    file_queue.join()

    # 通知线程退出
    stop_event.set()

    # 等待所有线程退出
    for thread in thread_list:
        thread.join()

    print("所有文件拉取完成！")

if __name__ == "__main__":
    # 文件队列
    file_queue = Queue()

    # 获取用户输入
    config = get_user_input()

    # 拉取文件
    pull_files(
        remote_path=config["remote_path"],
        pattern=config["pattern"],
        remote_host=config["remote_host"],
        remote_port=config["remote_port"],
        remote_user=config["remote_user"],
        remote_password=config["remote_password"],
        local_base_path=config["local_path"],
        threads=config["threads"],
    )
