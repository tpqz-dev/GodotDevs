import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path


project = Path(__file__).resolve().parent.parent
godot = sys.argv[1]
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
    probe.bind(("127.0.0.1", 0))
    port = str(probe.getsockname()[1])


def start(role, coordination_dir):
    return subprocess.Popen(
        [
            godot, "--headless", "--path", str(project),
            "--script", "res://tests/lobby_peer.gd", "--", role, port,
            str(coordination_dir),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
    )


with tempfile.TemporaryDirectory(prefix="godot-lobby-smoke-") as directory:
    coordination_dir = Path(directory)
    processes = []
    try:
        host = start("host", coordination_dir)
        processes.append(("host", host))
        time.sleep(0.8)
        for role in ("client1", "client2", "client3"):
            processes.append((role, start(role, coordination_dir)))
        deadline = time.monotonic() + 15
        while not (coordination_dir / "host_ready").exists():
            if host.poll() is not None or time.monotonic() >= deadline:
                break
            time.sleep(0.05)
        failed = not (coordination_dir / "host_ready").exists()
        if failed:
            print("Host never reached a ready four-player lobby; full-server test skipped.")
        else:
            processes.append(("full", start("full", coordination_dir)))
        for role, process in processes:
            try:
                output, _ = process.communicate(timeout=35)
            except subprocess.TimeoutExpired:
                process.kill()
                output, _ = process.communicate()
                print(f"--- {role} ---\n{output}\nProcess timed out.")
                failed = True
                continue
            print(f"--- {role} ---\n{output}")
            if process.returncode or "SCRIPT ERROR:" in output or "ERROR:" in output:
                failed = True
        sys.exit(1 if failed else 0)
    finally:
        for _, process in processes:
            if process.poll() is None:
                process.kill()
                process.wait()
