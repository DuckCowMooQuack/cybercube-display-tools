#!/usr/bin/env python3
"""Render Spotify now-playing art/text to a 240x240 GIF and publish it to a CyberCube."""

import argparse
import io
import json
import os
import signal
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from cybercube_dashboard import activate_file, get_cube_status, publish


DEFAULT_CUBE = os.environ.get("CYBERCUBE_IP", "192.168.4.26")
DEFAULT_OUTPUT = os.environ.get("CYBERCUBE_SPOTIFY_OUTPUT", "/tmp/cybercube_spotify.gif")
DEFAULT_TOKEN_PATH = os.environ.get(
    "CYBERCUBE_SPOTIFY_TOKEN_PATH",
    str(Path.home() / ".config" / "cybercube" / "spotify-token.json"),
)
DEFAULT_IDLE_PATH = os.environ.get("CYBERCUBE_IDLE_PATH", "/image/Starfield_1.gif")
UPLOAD_NAME = "cybercube_spotify.gif"
WIDTH = 240
HEIGHT = 240
LANCZOS = getattr(getattr(Image, "Resampling", Image), "LANCZOS")
ALBUM_ART_SIZE = 96
STOP_REQUESTED = threading.Event()


def http_json(url, method="GET", data=None, headers=None, timeout=15):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        body = response.read().decode("utf-8", errors="replace")
    return json.loads(body) if body else None


def read_token_cache(path):
    with open(path, "r", encoding="utf-8-sig") as f:
        token = json.load(f)
    if not token.get("client_id") or not token.get("refresh_token"):
        raise ValueError("Spotify token cache must contain client_id and refresh_token.")
    return token


def refresh_access_token(token):
    body = urllib.parse.urlencode(
        {
            "grant_type": "refresh_token",
            "refresh_token": token["refresh_token"],
            "client_id": token["client_id"],
        }
    ).encode("utf-8")
    data = http_json(
        "https://accounts.spotify.com/api/token",
        method="POST",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    access_token = data.get("access_token") if data else None
    if not access_token:
        raise ValueError("Spotify did not return an access token.")
    return access_token


def get_current_playback(access_token):
    try:
        return http_json(
            "https://api.spotify.com/v1/me/player/currently-playing",
            headers={"Authorization": "Bearer %s" % access_token},
            timeout=15,
        )
    except urllib.error.HTTPError as error:
        if error.code == 204:
            return None
        raise


def download_image(url):
    with urllib.request.urlopen(url, timeout=20) as response:
        return Image.open(io.BytesIO(response.read())).convert("RGB")


def font(size, bold=False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
    ]
    for candidate in candidates:
        if os.path.exists(candidate):
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def cover_square(img):
    src_w, src_h = img.size
    scale = max(WIDTH / src_w, HEIGHT / src_h)
    resized = img.resize((round(src_w * scale), round(src_h * scale)), LANCZOS)
    x = (resized.width - WIDTH) // 2
    y = (resized.height - HEIGHT) // 2
    return resized.crop((x, y, x + WIDTH, y + HEIGHT))


def fit_text(draw, text, max_width, max_size, min_size=13, bold=True):
    clean = " ".join(str(text or "").split())
    for size in range(max_size, min_size - 1, -1):
        fnt = font(size, bold=bold)
        if draw.textbbox((0, 0), clean, font=fnt)[2] <= max_width:
            return clean, fnt
    fnt = font(min_size, bold=bold)
    clipped = clean
    while clipped and draw.textbbox((0, 0), clipped + "...", font=fnt)[2] > max_width:
        clipped = clipped[:-1]
    return (clipped + "...") if clipped else clean[:10], fnt


def ellipsize(draw, text, fnt, max_width):
    if draw.textbbox((0, 0), text, font=fnt)[2] <= max_width:
        return text
    clipped = text
    while clipped and draw.textbbox((0, 0), clipped + "...", font=fnt)[2] > max_width:
        clipped = clipped[:-1]
    return (clipped + "...") if clipped else ""


def wrap_words(draw, text, fnt, max_width, max_lines):
    words = " ".join(str(text or "").split()).split()
    lines = []
    current = ""
    for word in words:
        candidate = word if not current else current + " " + word
        if draw.textbbox((0, 0), candidate, font=fnt)[2] <= max_width:
            current = candidate
            continue
        if current:
            lines.append(current)
        current = word
        if len(lines) == max_lines:
            break
    if current and len(lines) < max_lines:
        lines.append(current)
    if len(lines) > max_lines:
        lines = lines[:max_lines]
    return [ellipsize(draw, line, fnt, max_width) for line in lines]


def progress_bar(draw, playback):
    duration = playback.get("item", {}).get("duration_ms") or 0
    progress = playback.get("progress_ms") or 0
    ratio = 0 if duration <= 0 else max(0, min(1, progress / duration))
    draw.rounded_rectangle((14, 225, 226, 235), radius=5, fill=(15, 23, 42))
    draw.rounded_rectangle((14, 225, 14 + round(212 * ratio), 235), radius=5, fill=(30, 215, 96))


def render_now_playing(playback, output):
    item = playback.get("item") or {}
    title = item.get("name") or "Unknown track"
    artists = ", ".join(a.get("name", "") for a in item.get("artists", []) if a.get("name")) or "Unknown artist"
    images = item.get("album", {}).get("images", [])
    art_url = images[0]["url"] if images else None

    if art_url:
        cover = cover_square(download_image(art_url))
    else:
        cover = Image.new("RGB", (WIDTH, HEIGHT), (12, 16, 24))

    img = Image.new("RGB", (WIDTH, HEIGHT), (8, 12, 18))
    draw = ImageDraw.Draw(img, "RGBA")
    art = cover.resize((ALBUM_ART_SIZE, ALBUM_ART_SIZE), LANCZOS)
    art_x = (WIDTH - ALBUM_ART_SIZE) // 2
    art_y = 20
    draw.rounded_rectangle(
        (art_x - 3, art_y - 3, art_x + ALBUM_ART_SIZE + 3, art_y + ALBUM_ART_SIZE + 3),
        radius=8,
        fill=(0, 0, 0, 120),
        outline=(255, 255, 255, 75),
        width=2,
    )
    img.paste(art, (art_x, art_y))

    title_font = font(27, bold=True)
    artist_font = font(18)
    title_lines = wrap_words(draw, title, title_font, 212, 2)
    y = 126
    for line in title_lines:
        bbox = draw.textbbox((0, 0), line, font=title_font)
        draw.text(((WIDTH - (bbox[2] - bbox[0])) // 2, y), line, fill=(248, 250, 252, 255), font=title_font)
        y += 31

    artist_lines = wrap_words(draw, artists, artist_font, 212, 2)
    y += 2
    for line in artist_lines:
        bbox = draw.textbbox((0, 0), line, font=artist_font)
        draw.text(((WIDTH - (bbox[2] - bbox[0])) // 2, y), line, fill=(203, 213, 225, 245), font=artist_font)
        y += 21
    progress_bar(draw, playback)
    img.save(output, format="GIF", optimize=True)


def render_spotify(token_path, output):
    token = read_token_cache(token_path)
    access_token = refresh_access_token(token)
    playback = get_current_playback(access_token)
    if not playback or not playback.get("item") or not playback.get("is_playing"):
        return None
    render_now_playing(playback, output)
    return playback


def normalize_cube_path(path):
    return "/" + str(path or "").lstrip("/")


def is_active_path(status, path):
    active_path = status.get("album", {}).get("activePath")
    return normalize_cube_path(active_path) == normalize_cube_path(path)


def confirm_active_path(cube, path, attempts=5, delay=0.25):
    last_status = None
    for attempt in range(attempts):
        try:
            last_status = get_cube_status(cube)
        except (OSError, TimeoutError, urllib.error.URLError):
            if attempt == attempts - 1:
                raise
        else:
            if is_active_path(last_status, path):
                return last_status
        if attempt < attempts - 1:
            time.sleep(delay)
    return last_status


def activate_idle(args, previous_mode=None, reason="Spotify not actively playing"):
    if args.dry_run:
        if previous_mode == "starfield":
            print("mode: Starfield already active (%s)" % reason)
        else:
            print("mode: Starfield (%s)" % reason)
        return "starfield"

    try:
        status = get_cube_status(args.cube)
        if is_active_path(status, args.idle_path):
            if previous_mode == "starfield":
                print("mode: Starfield already active (%s)" % reason)
            else:
                print("mode: Starfield (%s)" % reason)
            print("active path: %s" % status.get("album", {}).get("activePath"))
            return "starfield"
    except (OSError, TimeoutError, urllib.error.URLError):
        status = None

    print("mode: Starfield (%s)" % reason)

    activate = activate_file(args.cube, args.idle_path)
    try:
        status = confirm_active_path(args.cube, args.idle_path)
    except (OSError, TimeoutError, urllib.error.URLError):
        status = {"album": {"activePath": args.idle_path}, "status_warning": "Could not confirm final status."}
    if status is None:
        status = {"album": {"activePath": args.idle_path}, "status_warning": "Could not confirm final status."}
    print("activate ok: %s" % activate.get("ok"))
    print("active path: %s" % status.get("album", {}).get("activePath"))
    return "starfield"


def run_once(args, previous_mode=None):
    playback = render_spotify(args.token_path, args.output)
    if playback and playback.get("item"):
        size = Path(args.output).stat().st_size
        item = playback["item"]
        artists = ", ".join(a.get("name", "") for a in item.get("artists", []) if a.get("name"))
        print("rendered: %s - %s (%s bytes)" % (artists, item.get("name", ""), size))

        if args.dry_run:
            return "spotify"

        upload, activate, status = publish(args.cube, args.output, upload_name=UPLOAD_NAME)
        print("upload ok: %s" % upload.get("ok"))
        print("activate ok: %s" % activate.get("ok"))
        print("active path: %s" % status.get("album", {}).get("activePath"))
        return "spotify"
    else:
        return activate_idle(args, previous_mode=previous_mode)


def request_stop(signum, _frame):
    print("shutdown requested: received signal %s" % signum, file=sys.stderr)
    STOP_REQUESTED.set()


def install_signal_handlers():
    for signal_name in ("SIGINT", "SIGTERM", "SIGHUP"):
        signum = getattr(signal, signal_name, None)
        if signum is not None:
            signal.signal(signum, request_stop)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cube", default=DEFAULT_CUBE, help="CyberCube IP address")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="local GIF path to render")
    parser.add_argument("--token-path", default=DEFAULT_TOKEN_PATH, help="Spotify token cache JSON path")
    parser.add_argument("--idle-path", default=DEFAULT_IDLE_PATH, help="CyberCube image path to activate when Spotify is not playing")
    parser.add_argument("--interval", type=int, default=0, help="seconds between updates; 0 runs once")
    parser.add_argument("--dry-run", action="store_true", help="render only; do not upload")
    parser.add_argument("--no-idle-on-exit", action="store_true", help="do not activate the idle path when the loop exits")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.interval <= 0:
        run_once(args)
        return

    install_signal_handlers()
    mode = None
    try:
        while not STOP_REQUESTED.is_set():
            started = time.time()
            try:
                mode = run_once(args, previous_mode=mode)
            except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
                print("update failed: %s" % error, file=sys.stderr)
            delay = max(1, args.interval - int(time.time() - started))
            STOP_REQUESTED.wait(delay)
    except KeyboardInterrupt:
        STOP_REQUESTED.set()
    finally:
        if not args.no_idle_on_exit:
            try:
                activate_idle(args, previous_mode=mode, reason="process exiting")
            except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
                print("exit cleanup failed: %s" % error, file=sys.stderr)


if __name__ == "__main__":
    main()
