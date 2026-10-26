#!/usr/bin/python3
"""Rotating wallpapers for GNOME with a separate image per monitor.

Usage: wallpaper [next|ban [all|landscape|portrait]|fetch [N]|status]
Settings are read from desktop.conf next to this script.
"""

import fcntl
import json
import os
import random
import shlex
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path

from gi.repository import Gio

SCRIPT_DIR = Path(os.path.realpath(__file__)).parent
CONFIG_FILE = SCRIPT_DIR / "desktop.conf"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "wallpaper"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "wallpaper"
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
ORIENTATIONS = ("landscape", "portrait")
USER_AGENT = "dev-environment-wallpaper/1.0"


def log(msg):
    print(f"[wallpaper] {msg}", file=sys.stderr)


def load_config():
    """Parse simple KEY=value lines of the bash config (arrays are ignored)."""
    cfg = {}
    for line in CONFIG_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, raw = line.partition("=")
        if not key.isidentifier() or raw.startswith("("):
            continue
        parts = shlex.split(raw, comments=True)
        cfg[key] = os.path.expanduser(os.path.expandvars(parts[0])) if parts else ""
    return cfg


def as_bool(value):
    return str(value).lower() in ("1", "true", "yes", "on")


# ---------- monitors ----------

def get_monitors():
    """Return monitors as dicts with x, y, w, h in layout coordinates plus render scale."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        reply = bus.call_sync(
            "org.gnome.Mutter.DisplayConfig", "/org/gnome/Mutter/DisplayConfig",
            "org.gnome.Mutter.DisplayConfig", "GetCurrentState",
            None, None, Gio.DBusCallFlags.NONE, -1, None,
        ).unpack()
    except Exception as exc:  # no Mutter (e.g. headless): assume one 1080p screen
        log(f"could not read monitor layout ({exc}), assuming 1920x1080")
        return [dict(name="default", x=0, y=0, w=1920, h=1080, scale=1.0)]

    _, physical, logical, props = reply
    logical_layout = props.get("layout-mode", 2) == 1
    modes = {}
    for (connector, *_), mode_list, _ in physical:
        for _, mw, mh, _, _, _, mprops in mode_list:
            if mprops.get("is-current"):
                modes[connector] = (mw, mh)

    monitors = []
    for x, y, scale, transform, _, members, _ in logical:
        connector = members[0][0]
        if connector not in modes:
            continue
        w, h = modes[connector]
        if transform % 2 == 1:  # rotated 90/270
            w, h = h, w
        if logical_layout:
            w, h = round(w / scale), round(h / scale)
        monitors.append(dict(name=connector, x=x, y=y, w=w, h=h, scale=scale if logical_layout else 1.0))
    return monitors or [dict(name="default", x=0, y=0, w=1920, h=1080, scale=1.0)]


def orientation_of(mon):
    return "portrait" if mon["h"] > mon["w"] else "landscape"


# ---------- state ----------

def load_state():
    try:
        return json.loads((STATE_DIR / "state.json").read_text())
    except (OSError, ValueError):
        return {"current": {}, "history": []}


def save_state(state):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    (STATE_DIR / "state.json").write_text(json.dumps(state, indent=2))


def load_banned():
    try:
        return set((STATE_DIR / "banned.txt").read_text().split())
    except OSError:
        return set()


def add_banned(names):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with open(STATE_DIR / "banned.txt", "a") as f:
        for name in names:
            f.write(name + "\n")


# ---------- pool ----------

def pool_dir(cfg, orientation):
    d = Path(cfg["WALLPAPER_DIR"]) / orientation
    d.mkdir(parents=True, exist_ok=True)
    return d


def list_pool(cfg, orientation, banned):
    return [
        p for p in pool_dir(cfg, orientation).iterdir()
        if p.suffix.lower() in IMAGE_EXTS and p.name not in banned
    ]


def is_downloaded(path):
    return Path(path).name.startswith("wallhaven-")


def prune_pool(cfg, orientation, keep):
    limit = int(cfg.get("WALLPAPER_CACHE_MAX", 150))
    downloaded = sorted(
        (p for p in pool_dir(cfg, orientation).iterdir() if is_downloaded(p) and str(p) not in keep),
        key=lambda p: p.stat().st_mtime,
    )
    for p in downloaded[: max(0, len(downloaded) - limit)]:
        p.unlink(missing_ok=True)


# ---------- wallhaven ----------

def http_get(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def wallhaven_search(cfg, topic, orientation, min_res, page=1):
    excluded = [t.strip() for t in cfg.get("WALLPAPER_EXCLUDE", "").split(",") if t.strip()]
    params = {
        "q": " ".join([topic] + [f"-{t}" for t in excluded]),
        "categories": cfg.get("WALLHAVEN_CATEGORIES", "100"),
        "purity": cfg.get("WALLHAVEN_PURITY", "100"),
        "sorting": cfg.get("WALLHAVEN_SORTING", "toplist"),
        "ratios": orientation,
        "atleast": f"{min_res[0]}x{min_res[1]}",
        "page": page,
    }
    if params["sorting"] == "toplist":
        params["topRange"] = cfg.get("WALLHAVEN_TOP_RANGE", "1y")
    if cfg.get("WALLHAVEN_API_KEY"):
        params["apikey"] = cfg["WALLHAVEN_API_KEY"]
    url = "https://wallhaven.cc/api/v1/search?" + urllib.parse.urlencode(params)
    return json.loads(http_get(url))


def fetch_one(cfg, orientation, min_res, banned):
    """Download one new image for the orientation. Returns its path or None."""
    topics = [t.strip() for t in cfg.get("WALLPAPER_TOPICS", "").split(",") if t.strip()] or ["landscape"]
    existing = {p.name for p in pool_dir(cfg, orientation).iterdir()} | banned
    for _ in range(4):
        topic = random.choice(topics)
        try:
            first = wallhaven_search(cfg, topic, orientation, min_res)
            last_page = min(first["meta"].get("last_page", 1), 10)
            page = random.randint(1, last_page)
            data = first if page == 1 else wallhaven_search(cfg, topic, orientation, min_res, page)
        except Exception as exc:
            log(f"wallhaven search failed: {exc}")
            return None
        candidates = [w for w in data.get("data", []) if Path(w["path"]).name not in existing]
        if not candidates:
            continue
        item = random.choice(candidates)
        dest = pool_dir(cfg, orientation) / Path(item["path"]).name
        try:
            content = http_get(item["path"], timeout=120)
        except Exception as exc:
            log(f"download failed: {exc}")
            return None
        tmp = dest.with_suffix(dest.suffix + ".part")
        tmp.write_bytes(content)
        tmp.rename(dest)
        log(f"downloaded {dest.name} ({topic}, {item['resolution']})")
        return dest
    return None


# ---------- applying ----------

def min_resolution(monitors, orientation):
    sizes = [(round(m["w"] * m["scale"]), round(m["h"] * m["scale"])) for m in monitors if orientation_of(m) == orientation]
    return (max(s[0] for s in sizes), max(s[1] for s in sizes)) if sizes else (1920, 1080)


def pick(pool, history, exclude):
    recent = set(history)
    for candidates in (
        [p for p in pool if str(p) not in recent and str(p) not in exclude],
        [p for p in pool if str(p) not in exclude],
        pool,
    ):
        if candidates:
            return random.choice(candidates)
    return None


def compose_span(monitors, images, out):
    """Render each image cropped to its monitor and place them on one spanned canvas."""
    factor = max(m["scale"] for m in monitors)
    min_x = min(m["x"] for m in monitors)
    min_y = min(m["y"] for m in monitors)
    width = round(max(m["x"] + m["w"] for m in monitors) - min_x) * factor
    height = round(max(m["y"] + m["h"] for m in monitors) - min_y) * factor
    with tempfile.TemporaryDirectory() as tmp:
        cmd = ["convert", "-size", f"{int(width)}x{int(height)}", "xc:black"]
        for i, (mon, img) in enumerate(zip(monitors, images)):
            w, h = round(mon["w"] * factor), round(mon["h"] * factor)
            part = f"{tmp}/{i}.png"
            subprocess.run(
                ["convert", f"{img}[0]", "-resize", f"{w}x{h}^", "-gravity", "center", "-extent", f"{w}x{h}", part],
                check=True,
            )
            x, y = round((mon["x"] - min_x) * factor), round((mon["y"] - min_y) * factor)
            cmd += [part, "-geometry", f"+{x}+{y}", "-composite"]
        cmd += ["-quality", "92", str(out)]
        subprocess.run(cmd, check=True)


def set_background(path, option):
    uri = Path(path).as_uri()
    s = Gio.Settings.new("org.gnome.desktop.background")
    s.set_string("picture-uri", uri)
    s.set_string("picture-uri-dark", uri)
    s.set_string("picture-options", option)
    Gio.Settings.sync()


def apply(cfg, state, keep=None):
    """Pick and set new images. Monitors listed in `keep` reuse their current image."""
    keep = keep or {}
    monitors = get_monitors()
    per_monitor = as_bool(cfg.get("WALLPAPER_PER_MONITOR", "true")) and len(monitors) > 1
    banned = load_banned()
    online = as_bool(cfg.get("WALLPAPER_ONLINE", "true"))
    targets = monitors if per_monitor else [max(monitors, key=lambda m: m["w"] * m["h"])]
    history = state.get("history", [])

    chosen = []
    for mon in targets:
        if Path(keep.get(mon["name"], "")).is_file():
            chosen.append(keep[mon["name"]])
            continue
        orientation = orientation_of(mon)
        pool = list_pool(cfg, orientation, banned)
        unseen = [p for p in pool if str(p) not in history and str(p) not in chosen]
        if not unseen and online:
            new = fetch_one(cfg, orientation, min_resolution(monitors, orientation), banned)
            if new:
                pool.append(new)
        img = pick(pool, history, set(chosen))
        if img is None:
            log(f"no {orientation} images in {pool_dir(cfg, orientation)}")
            return False
        chosen.append(str(img))

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    if per_monitor:
        # A new filename each time so GNOME notices the change.
        out = CACHE_DIR / f"span-{int(time.time())}.jpg"
        compose_span(targets, chosen, out)
        set_background(out, "spanned")
        for old in CACHE_DIR.glob("span-*.jpg"):
            if old != out:
                old.unlink(missing_ok=True)
    else:
        set_background(chosen[0], "zoom")

    state["current"] = {mon["name"]: img for mon, img in zip(targets, chosen)}
    keep = int(cfg.get("WALLPAPER_HISTORY", 30))
    state["history"] = (history + chosen)[-keep:]
    save_state(state)
    log("applied " + ", ".join(f"{m['name']}={Path(i).name}" for m, i in zip(targets, chosen)))
    return True


def prefetch(cfg):
    """Download one image per orientation so the next change is instant, then prune old ones."""
    if not as_bool(cfg.get("WALLPAPER_ONLINE", "true")):
        return
    monitors = get_monitors()
    history = set(load_state().get("history", []))
    for orientation in {orientation_of(m) for m in monitors}:
        fetch_one(cfg, orientation, min_resolution(monitors, orientation), load_banned())
        prune_pool(cfg, orientation, keep=history)


# ---------- commands ----------

def cmd_next(cfg):
    return apply(cfg, load_state())


def cmd_ban(cfg, which="all"):
    state = load_state()
    current = state.get("current", {})
    victims = {
        name: Path(p) for name, p in current.items()
        if which == "all" or Path(p).parent.name == which
    }
    add_banned(p.name for p in victims.values())
    for p in victims.values():
        if is_downloaded(p):
            p.unlink(missing_ok=True)
        log(f"banned {p.name}")
    keep = {name: p for name, p in current.items() if name not in victims}
    return apply(cfg, state, keep)


def cmd_fetch(cfg, count="5"):
    monitors = get_monitors()
    banned = load_banned()
    for orientation in {orientation_of(m) for m in monitors}:
        for _ in range(int(count)):
            fetch_one(cfg, orientation, min_resolution(monitors, orientation), banned)
    return True


def cmd_status(cfg):
    state = load_state()
    banned = load_banned()
    for name, img in state.get("current", {}).items():
        print(f"{name}: {img}")
    for orientation in ORIENTATIONS:
        print(f"{orientation} pool: {len(list_pool(cfg, orientation, banned))} images")
    print(f"banned: {len(banned)}")
    return True


def main():
    args = sys.argv[1:] or ["next"]
    commands = {"next": cmd_next, "ban": cmd_ban, "fetch": cmd_fetch, "status": cmd_status}
    if args[0] not in commands:
        print(__doc__.strip())
        return 1
    cfg = load_config()
    if args[0] == "status":
        return 0 if cmd_status(cfg) else 1
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with open(STATE_DIR / "lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log("another run is in progress")
            return 0
        ok = commands[args[0]](cfg, *args[1:])
    if args[0] in ("next", "ban"):
        with open(STATE_DIR / "fetch.lock", "w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                prefetch(cfg)
            except BlockingIOError:
                pass
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
