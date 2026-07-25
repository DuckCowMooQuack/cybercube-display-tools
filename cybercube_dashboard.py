#!/usr/bin/env python3
"""Render system status to a 240x240 GIF and publish it to a Quboox Cyber Cube."""

import argparse
import http.client
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path
from uuid import uuid4

from PIL import Image, ImageDraw, ImageFont


DEFAULT_CUBE = os.environ.get("CYBERCUBE_IP", "192.168.4.26")
DEFAULT_OUTPUT = os.environ.get("CYBERCUBE_DASHBOARD_OUTPUT", "/tmp/cybercube_status.gif")
UPLOAD_NAME = "cybercube_status.gif"
WIDTH = 240
HEIGHT = 240


def http_json(url, timeout=10, data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        try:
            raw = response.read()
        except http.client.IncompleteRead as error:
            raw = error.partial
        body = raw.decode("utf-8", errors="replace")
    return json.loads(body) if body else {}


def upload_file(cube, path, timeout=30, upload_name=UPLOAD_NAME):
    boundary = "----cybercube-%s" % uuid4().hex
    payload = bytearray()
    payload.extend(("--%s\r\n" % boundary).encode("ascii"))
    part_header = (
        'Content-Disposition: form-data; name="file"; filename="%s"\r\n'
        "Content-Type: image/gif\r\n\r\n"
    ) % upload_name
    payload.extend(part_header.encode("ascii"))
    payload.extend(Path(path).read_bytes())
    payload.extend(("\r\n--%s--\r\n" % boundary).encode("ascii"))

    return http_json(
        "http://%s/api/upload?dir=image" % cube,
        timeout=timeout,
        data=bytes(payload),
        headers={"Content-Type": "multipart/form-data; boundary=%s" % boundary},
    )


def activate_file(cube, path):
    encoded = urllib.parse.quote(path, safe="")
    return http_json("http://%s/api/activate?dir=image&path=%s" % (cube, encoded))


def get_cube_status(cube):
    return http_json("http://%s/api/status" % cube, timeout=8)


def format_bytes(value):
    value = float(value or 0)
    units = ["B", "KB", "MB", "GB", "TB"]
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return "%d%s" % (round(value), unit) if unit == "B" else "%.1f%s" % (value, unit)
        value /= 1024


def read_linux_cpu_times():
    with open("/proc/stat", "r", encoding="utf-8") as f:
        parts = f.readline().split()[1:]
    nums = [int(p) for p in parts]
    idle = nums[3] + (nums[4] if len(nums) > 4 else 0)
    total = sum(nums)
    return idle, total


def linux_cpu_percent():
    idle1, total1 = read_linux_cpu_times()
    time.sleep(0.25)
    idle2, total2 = read_linux_cpu_times()
    idle_delta = idle2 - idle1
    total_delta = total2 - total1
    if total_delta <= 0:
        return 0
    return round((1 - idle_delta / total_delta) * 100)


def linux_mem():
    values = {}
    with open("/proc/meminfo", "r", encoding="utf-8") as f:
        for line in f:
            key, rest = line.split(":", 1)
            values[key] = int(rest.strip().split()[0]) * 1024
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", 0)
    return total - available, total


def linux_uptime():
    with open("/proc/uptime", "r", encoding="utf-8") as f:
        seconds = float(f.read().split()[0])
    days = int(seconds // 86400)
    hours = int((seconds % 86400) // 3600)
    return "%dd %dh" % (days, hours)


def collect_linux_metrics():
    disk = shutil.disk_usage("/")
    mem_used, mem_total = linux_mem()
    load = os.getloadavg()[0] if hasattr(os, "getloadavg") else 0
    return {
        "source": "Linux",
        "host": socket.gethostname().split(".")[0],
        "cpu": linux_cpu_percent(),
        "mem_used": mem_used,
        "mem_total": mem_total,
        "disk_used": disk.used,
        "disk_total": disk.total,
        "uptime": linux_uptime(),
        "load": "%.2f" % load,
    }


def collect_windows_metrics():
    ps = r"""
$os = Get-CimInstance Win32_OperatingSystem
$cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$uptime = (Get-Date) - $os.LastBootUpTime
[pscustomobject]@{
  source = 'Windows'
  host = $env:COMPUTERNAME
  cpu = [int][math]::Round($cpu)
  mem_used = [double](($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 1024)
  mem_total = [double]($os.TotalVisibleMemorySize * 1024)
  disk_used = [double]($disk.Size - $disk.FreeSpace)
  disk_total = [double]$disk.Size
  uptime = ('{0}d {1}h' -f [int]$uptime.TotalDays, $uptime.Hours)
  load = ''
} | ConvertTo-Json -Compress
"""
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", ps],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=8,
    )
    return json.loads(result.stdout)


def collect_metrics(source):
    if source in ("auto", "windows"):
        if shutil.which("powershell.exe"):
            try:
                return collect_windows_metrics()
            except Exception:
                if source == "windows":
                    raise
    return collect_linux_metrics()


def pct(used, total):
    return 0 if not total else max(0, min(100, round((used / total) * 100)))


def font(size, bold=False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
    ]
    for candidate in candidates:
        if os.path.exists(candidate):
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def draw_bar(draw, xy, value, fill):
    x, y, w, h = xy
    draw.rounded_rectangle((x, y, x + w, y + h), radius=6, fill=(31, 41, 55), outline=(55, 65, 81))
    inner = max(2, round((w - 4) * value / 100))
    draw.rounded_rectangle((x + 2, y + 2, x + 2 + inner, y + h - 2), radius=5, fill=fill)


def render_dashboard(metrics, output):
    img = Image.new("RGB", (WIDTH, HEIGHT), (8, 12, 18))
    draw = ImageDraw.Draw(img)

    title_font = font(18, bold=True)
    label_font = font(21, bold=True)
    value_font = font(32, bold=True)
    time_font = font(19, bold=True)

    rows = [
        ("CPU", int(metrics["cpu"]), (56, 189, 248)),
        (
            "RAM",
            pct(metrics["mem_used"], metrics["mem_total"]),
            (52, 211, 153),
        ),
        (
            "DISK",
            pct(metrics["disk_used"], metrics["disk_total"]),
            (251, 146, 60),
        ),
    ]

    draw.text((14, 10), "SYSTEM", fill=(226, 232, 240), font=title_font)
    draw.text((158, 9), datetime.now().strftime("%H:%M"), fill=(248, 250, 252), font=time_font)

    y = 47
    for label, percent, color in rows:
        draw.text((14, y), label, fill=color, font=label_font)
        value = "%d%%" % percent
        bbox = draw.textbbox((0, 0), value, font=value_font)
        draw.text((226 - (bbox[2] - bbox[0]), y - 7), value, fill=(248, 250, 252), font=value_font)
        draw_bar(draw, (14, y + 31, 212, 18), percent, color)
        y += 62

    img.save(output, format="GIF", optimize=True)


def publish(cube, output, upload_name=UPLOAD_NAME):
    upload = upload_file(cube, output, upload_name=upload_name)
    files = upload.get("files", [])
    uploaded = next((item for item in files if item.get("name") == upload_name), None)
    path = uploaded.get("path") if uploaded else "/image/%s" % upload_name
    activate = activate_file(cube, path)
    try:
        status = get_cube_status(cube)
    except (OSError, TimeoutError, urllib.error.URLError):
        status = {"album": {"activePath": path}, "status_warning": "Could not confirm final status."}
    return upload, activate, status


def run_once(args):
    metrics = collect_metrics(args.source)
    render_dashboard(metrics, args.output)
    size = Path(args.output).stat().st_size
    print("rendered %s (%s bytes)" % (args.output, size))

    if args.dry_run:
        return

    upload, activate, status = publish(args.cube, args.output)
    active = status.get("album", {}).get("activePath")
    print("upload ok: %s" % upload.get("ok"))
    print("activate ok: %s" % activate.get("ok"))
    print("active path: %s" % active)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cube", default=DEFAULT_CUBE, help="CyberCube IP address")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="local GIF path to render")
    parser.add_argument("--source", choices=["auto", "windows", "linux"], default="auto")
    parser.add_argument("--interval", type=int, default=0, help="seconds between updates; 0 runs once")
    parser.add_argument("--dry-run", action="store_true", help="render only; do not upload")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.interval <= 0:
        run_once(args)
        return

    while True:
        started = time.time()
        try:
            run_once(args)
        except (urllib.error.URLError, TimeoutError, subprocess.SubprocessError, OSError, ValueError) as error:
            print("update failed: %s" % error, file=sys.stderr)
        delay = max(1, args.interval - int(time.time() - started))
        time.sleep(delay)


if __name__ == "__main__":
    main()
