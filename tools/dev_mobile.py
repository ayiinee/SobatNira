"""Run Flutter Chrome from the repo root and reload when Dart files change."""

import argparse
import json
from pathlib import Path
import queue
import shutil
import socket
import subprocess
import sys
import threading
import time


ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "apps" / "mobile"


def snapshot():
    files = {}
    for path in (MOBILE / "lib").rglob("*.dart"):
        try:
            stat = path.stat()
            files[str(path)] = (stat.st_mtime_ns, stat.st_size)
        except FileNotFoundError:
            pass
    return files


def send(process, request_id, method, app_id, **params):
    process.stdin.write(json.dumps([{
        "id": request_id,
        "method": method,
        "params": {"appId": app_id, **params},
    }]) + "\n")
    process.stdin.flush()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int)
    parser.add_argument("--connected", action="store_true", help="Gunakan Supabase dan API dari .env akar repo.")
    args = parser.parse_args()
    if args.port is None:
        args.port = 8080 if args.connected else 8085
    if not 1 <= args.port <= 65535:
        parser.error("Port harus antara 1 dan 65535.")
    flutter = shutil.which("flutter")
    if not flutter:
        parser.exit(1, "Flutter tidak ditemukan di PATH.\n")
    with socket.socket() as probe:
        if probe.connect_ex(("127.0.0.1", args.port)) == 0:
            parser.exit(1, f"Port {args.port} sedang dipakai. Hentikan Flutter lama dengan q atau pilih --port lain.\n")

    command = [flutter, "run", "-d", "chrome", "--web-hostname", "127.0.0.1",
               "--web-port", str(args.port), "--hot", "--machine"]
    if args.connected:
        node = shutil.which("node")
        if not node:
            parser.exit(1, "Node.js 24 diperlukan untuk membaca .env.\n")
        configured = subprocess.run([node, str(ROOT / "tools" / "mobile_config.mjs")], cwd=ROOT)
        if configured.returncode:
            return configured.returncode
        command.append(f"--dart-define-from-file={ROOT / '.tmp' / 'mobile' / 'public-defines.json'}")

    previous = snapshot()
    process = subprocess.Popen(
        command,
        cwd=MOBILE,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if sys.platform == "win32" else 0,
    )
    messages = queue.Queue()

    def read_output():
        for line in process.stdout:
            messages.put(line.rstrip())

    threading.Thread(target=read_output, daemon=True).start()
    app_id = None
    ready = False
    dirty_at = None
    request_id = 0
    pending = None
    print(f"SobatNira otomatis: http://127.0.0.1:{args.port}", flush=True)
    print("Pantau perubahan apps/mobile/lib. Tekan Ctrl+C untuk berhenti.", flush=True)
    try:
        while process.poll() is None or not messages.empty():
            try:
                line = messages.get(timeout=.2)
            except queue.Empty:
                line = ""
            try:
                decoded = json.loads(line)
            except (ValueError, TypeError):
                decoded = None
            if isinstance(decoded, list):
                for event in decoded:
                    name = event.get("event")
                    params = event.get("params", {})
                    if name == "app.start":
                        app_id = params["appId"]
                    elif name == "app.started":
                        ready = True
                        print("Siap. Simpan/edit file Dart: Chrome akan diperbarui otomatis.", flush=True)
                    elif name in ("app.log", "daemon.log", "app.progress"):
                        message = params.get("log") or params.get("message")
                        if message and not params.get("finished"):
                            print(message, flush=True)
                    elif pending is not None and event.get("id") == pending:
                        pending = None
                        result = event.get("result") or {}
                        if "error" in event or result.get("code", 0) != 0:
                            print("Reload belum berhasil. Perbaiki error di atas, lalu simpan lagi.", flush=True)
                        else:
                            print("Hot reload selesai.", flush=True)
            elif line:
                print(line, flush=True)

            current = snapshot()
            if current != previous:
                previous = current
                dirty_at = time.monotonic()
            if ready and app_id and pending is None and dirty_at is not None and time.monotonic() - dirty_at >= .7:
                request_id += 1
                send(process, request_id, "app.restart", app_id, fullRestart=False, pause=False, reason="file-change")
                pending = request_id
                dirty_at = None
                print("Perubahan terdeteksi, hot reload...", flush=True)
    except KeyboardInterrupt:
        print("\nMenghentikan Flutter...", flush=True)
    finally:
        if process.poll() is None:
            try:
                if app_id:
                    send(process, request_id + 1, "app.stop", app_id)
                process.stdin.close()
                process.wait(timeout=8)
            except (OSError, subprocess.TimeoutExpired):
                if sys.platform == "win32":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
                else:
                    process.kill()
    return process.returncode or 0


if __name__ == "__main__":
    raise SystemExit(main())
