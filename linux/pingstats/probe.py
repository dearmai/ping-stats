"""Linux probes, isolated in a subprocess to bound DNS and HTTP total time."""
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def parse_address(address):
    address = address.strip()
    if not address or address.startswith("-"):
        raise ValueError("Invalid address")
    if address.lower().startswith(("http://", "https://")):
        url = urllib.parse.urlsplit(address)
        if not url.hostname:
            raise ValueError("Invalid HTTP URL")
        return "http", address, None
    try:
        ipaddress.ip_address(address)
        return "ping", address, None
    except ValueError:
        pass
    if ":" in address:
        host, port = address.rsplit(":", 1)
        host = host.removeprefix("[").removesuffix("]")
        if not host or not port.isdigit() or not 1 <= int(port) <= 65535:
            raise ValueError("Use host:port with a port from 1 to 65535")
        return "tcp", host, int(port)
    return "ping", address, None


def _probe(address, timeout):
    mode, host, port = parse_address(address)
    start = time.monotonic()
    if mode == "http":
        try:
            with urllib.request.urlopen(host, timeout=timeout) as response:
                status = response.status
                while response.read(65536):
                    pass
        except urllib.error.HTTPError as error:
            status = error.code
            error.close()
        if not 200 <= status < 400:
            raise ValueError("HTTP %s" % status)
    elif mode == "tcp":
        with socket.create_connection((host, port), timeout=timeout):
            pass
    else:
        executable = shutil.which("ping")
        if not executable:
            raise ValueError("ping not found; install iputils")
        result = subprocess.run([executable, "-n", "-c", "1", "-W", str(timeout), host],
                                capture_output=True, text=True, timeout=timeout,
                                env=dict(os.environ, LC_ALL="C"))
        if result.returncode:
            raise ValueError((result.stderr or result.stdout).strip()[-500:] or "Ping failed")
        match = re.search(r"time[=<]([\d.]+)", result.stdout)
        if match:
            return float(match.group(1))
    return (time.monotonic() - start) * 1000


def probe(address, timeout):
    # A process deadline also covers DNS resolution and slow streaming HTTP bodies.
    # The nested ping has its own timeout; no shell interprets the target address.
    try:
        result = subprocess.run([sys.executable, "-m", "pingstats.probe", address, str(timeout)],
                                capture_output=True, text=True, timeout=timeout + .3,
                                env=dict(os.environ, PYTHONPATH=str(Path(__file__).resolve().parent.parent)))
        if result.returncode:
            return None, result.stderr.strip()[-500:] or "Probe failed"
        return tuple(json.loads(result.stdout))
    except subprocess.TimeoutExpired:
        return None, "Timeout"
    except (OSError, ValueError) as error:
        return None, str(error)


def local_addresses():
    try:
        result = subprocess.run(["ip", "-j", "address", "show", "up"],
                                capture_output=True, text=True, timeout=2, check=True)
        addresses = []
        for interface in json.loads(result.stdout):
            if "LOOPBACK" in interface.get("flags", []):
                continue
            for info in interface.get("addr_info", []):
                addr = ipaddress.ip_address(info["local"])
                if not (addr.is_link_local or addr.is_loopback or addr.is_unspecified):
                    addresses.append((interface["ifname"], str(addr)))
        return sorted(addresses, key=lambda pair: (pair[0], ":" in pair[1], pair[1]))
    except (OSError, ValueError, subprocess.SubprocessError):
        return []


if __name__ == "__main__":
    try:
        print(json.dumps([_probe(sys.argv[1], float(sys.argv[2])), None]))
    except Exception as error:
        print(json.dumps([None, "Timeout" if isinstance(error, (TimeoutError, subprocess.TimeoutExpired)) else str(error)]))
