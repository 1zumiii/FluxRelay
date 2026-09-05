#!/usr/bin/env python3
"""Validate bundled aria2 engine contracts without touching the live engine."""

from __future__ import annotations

import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path(os.environ.get("ARIA2_BINARY", ROOT / "Resources/engine/aria2c"))
CONFIG = ROOT / "Resources/engine/aria2.conf"
TOKEN = "motrix-native-regression"
RPC_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def rpc(port: int, method: str, *params):
    body = json.dumps({
        "jsonrpc": "2.0",
        "id": method,
        "method": method,
        "params": [f"token:{TOKEN}", *params],
    }).encode()
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/jsonrpc",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with RPC_OPENER.open(request, timeout=2) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise RuntimeError(f"{method}: HTTP {error.code}: {detail}") from error
    if "error" in result:
        raise RuntimeError(f"{method}: {result['error']}")
    return result["result"]


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


def start_server(directory: Path, tls: tuple[Path, Path] | None = None):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), QuietHandler)
    server.directory = str(directory)
    # SimpleHTTPRequestHandler reads its directory from the handler instance.
    server.RequestHandlerClass = lambda *args, **kwargs: QuietHandler(
        *args, directory=str(directory), **kwargs
    )
    if tls:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(tls[0], tls[1])
        server.socket = context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread


def wait_rpc(port: int) -> None:
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        try:
            rpc(port, "aria2.getVersion")
            return
        except (OSError, urllib.error.URLError, RuntimeError):
            time.sleep(0.1)
    raise RuntimeError("aria2 RPC did not become ready")


def wait_status(port: int, gid: str, wanted: set[str], timeout: float = 12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = rpc(port, "aria2.tellStatus", gid, ["status", "errorCode", "errorMessage", "filename"])
        if status["status"] in wanted:
            return status
        time.sleep(0.1)
    raise RuntimeError(f"timed out waiting for {gid}")


def assert_config():
    values = {}
    for line in CONFIG.read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().lower()
    if values.get("check-certificate") != "true":
        raise RuntimeError("bundled aria2.conf must set check-certificate=true")


def main() -> int:
    if not ENGINE.is_file() or not os.access(ENGINE, os.X_OK):
        raise RuntimeError(f"missing executable engine: {ENGINE}")
    assert_config()

    root = Path(tempfile.mkdtemp(prefix="motrix-native-aria2-regressions-"))
    engine = None
    servers = []
    try:
        source = root / "source"
        download = root / "download"
        source.mkdir()
        download.mkdir()
        for index in range(25):
            (source / f"history-{index:02d}.txt").write_text(f"history {index}\n")

        cert = root / "localhost.pem"
        key = root / "localhost-key.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", str(key), "-out", str(cert), "-days", "1",
            "-subj", "/CN=localhost",
            "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        http_server, _ = start_server(source)
        servers.append(http_server)
        https_server, _ = start_server(source, (cert, key))
        servers.append(https_server)
        http_port = http_server.server_address[1]
        https_port = https_server.server_address[1]
        rpc_port = free_port()

        engine_env = os.environ.copy()
        for variable in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"):
            engine_env.pop(variable, None)
        engine = subprocess.Popen([
            str(ENGINE), f"--conf-path={CONFIG}",
            "--enable-rpc=true", "--rpc-listen-all=false", f"--rpc-listen-port={rpc_port}",
            f"--rpc-secret={TOKEN}", f"--dir={download}",
            "--enable-dht=false", "--enable-dht6=false", "--disable-ipv6=true", "--bt-enable-lpd=false",
            "--no-proxy=localhost,127.0.0.1,::1", "--file-allocation=none",
            "--max-tries=1", "--retry-wait=0", "--connect-timeout=2", "--timeout=2",
            "--all-proxy=", "--http-proxy=", "--https-proxy=", "--ftp-proxy=",
            "--console-log-level=warn", "--summary-interval=0",
        ], cwd=root, env=engine_env, stdout=subprocess.DEVNULL,
            stderr=(root / "aria2.log").open("w"), text=True)
        wait_rpc(rpc_port)
        options = rpc(rpc_port, "aria2.getGlobalOption")
        if options.get("check-certificate") != "true":
            raise RuntimeError(f"aria2 runtime did not report check-certificate=true: {options}")

        tls_gid = rpc(rpc_port, "aria2.addUri", [f"https://127.0.0.1:{https_port}/history-00.txt"])
        tls_status = wait_status(rpc_port, tls_gid, {"complete", "error", "removed"})
        if tls_status["status"] == "complete":
            raise RuntimeError("self-signed HTTPS download unexpectedly completed")
        # AppleTLS reports invalid chains as generic handshake error 1;
        # other backends use aria2's certificate error 24. Reject unrelated
        # connection failures so an unavailable test server cannot pass.
        certificate_error = tls_status.get("errorCode") == "24" or (
            tls_status.get("errorCode") == "1"
            and "invalid certificate chain" in tls_status.get("errorMessage", "").lower()
        )
        if tls_status["status"] != "error" or not certificate_error:
            raise RuntimeError(f"self-signed HTTPS download did not fail certificate validation: {tls_status}")

        # Trust this fixture certificate in this one test client only, proving
        # the same HTTPS endpoint is healthy without changing the OS trust store.
        control = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile=str(cert))),
        )
        with control.open(f"https://127.0.0.1:{https_port}/history-00.txt", timeout=3) as response:
            if response.read() != (source / "history-00.txt").read_bytes():
                raise RuntimeError("HTTPS fixture returned unexpected content")

        for index in range(25):
            gid = rpc(rpc_port, "aria2.addUri", [f"http://127.0.0.1:{http_port}/history-{index:02d}.txt"])
            status = wait_status(rpc_port, gid, {"complete", "error"})
            if status["status"] != "complete":
                raise RuntimeError(f"history download failed: {status}")

        completed = []
        offset = -1
        while True:
            # aria2 retains completed jobs in tellStopped, newest first.
            page = rpc(rpc_port, "aria2.tellStopped", offset, 7, ["status", "files"])
            completed.extend(page)
            if len(page) < 7:
                break
            offset -= len(page)
        history_names = [Path(item["files"][0]["path"]).name for item in completed]
        expected = [f"history-{index:02d}.txt" for index in range(24, -1, -1)]
        observed = [name for name in history_names if name in set(expected)]
        if observed != expected:
            raise RuntimeError(f"completed history order/content mismatch: {observed}")

        # Exercise the compact snapshot and checksum contracts used by the UI.
        summaries = rpc(rpc_port, "aria2.tellStopped", -1, 100, ["gid", "status", "totalLength"])
        if any("files" in item or "bitfield" in item for item in summaries):
            raise RuntimeError("summary RPC unexpectedly returned detail fields")
        detail = rpc(rpc_port, "aria2.tellStatus", summaries[0]["gid"], ["gid", "files", "bitfield"])
        if not detail.get("files"):
            raise RuntimeError("on-demand file details are missing")
        uri = f"http://127.0.0.1:{http_port}/history-00.txt"
        bad = rpc(rpc_port, "aria2.addUri", [uri], {"out": "checksum-bad.txt", "checksum": "sha-256=" + "0" * 64})
        failed = wait_status(rpc_port, bad, {"complete", "error"})
        if failed.get("errorCode") != "32":
            raise RuntimeError(f"checksum mismatch must report code 32: {failed}")
        digest = hashlib.sha256((source / "history-00.txt").read_bytes()).hexdigest()
        good = rpc(rpc_port, "aria2.addUri", [uri], {"out": "checksum-good.txt", "checksum": "sha-256=" + digest})
        if wait_status(rpc_port, good, {"complete", "error"})["status"] != "complete":
            raise RuntimeError("valid checksum did not complete")

        for index in range(21):
            rpc(rpc_port, "aria2.addUri", [f"http://127.0.0.1:{http_port}/queued-{index:02d}.txt"], {"pause": "true"})
        waiting = rpc(rpc_port, "aria2.tellWaiting", 0, 100, ["status"])
        paused_count = sum(item["status"] == "paused" for item in waiting)
        if paused_count < 21:
            raise RuntimeError(f"queued task contract did not retain more than 20 paused tasks ({len(waiting)} returned, {paused_count} paused)")

        rpc(rpc_port, "aria2.shutdown")
        engine.wait(timeout=5)
        engine = None
        print("aria2 regression contracts passed (TLS validation, completed history, queued tasks, summary/detail fields, checksums).")
        return 0
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()
        if engine is not None:
            engine.terminate()
            try:
                engine.wait(timeout=3)
            except subprocess.TimeoutExpired:
                engine.kill()
                engine.wait()
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"aria2 regression contracts failed: {error}", file=sys.stderr)
        raise SystemExit(1)
