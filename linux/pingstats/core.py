"""Platform-independent settings, health evaluation and notification rules."""
import json
import math
import os
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path

NORMAL = {"green", "blue"}
DEFAULTS = dict(backgroundInterval=5, backgroundTimeout=3, foregroundInterval=1,
                foregroundTimeout=1, chartWindowSeconds=600, greenLatencyMs=60,
                blueLatencyMs=120)


def target(address, name=""):
    return dict(id=str(uuid.uuid4()), name=name, address=address,
                isEnabled=True, notifyLevels=["warning", "error"])


def normalize(raw):
    if not isinstance(raw, dict):
        raise ValueError("Settings must be a JSON object")
    result = dict(DEFAULTS)
    bounds = dict(backgroundInterval=(1, None), backgroundTimeout=(.2, None),
                  foregroundInterval=(.5, None), foregroundTimeout=(.2, None),
                  chartWindowSeconds=(60, 3600), greenLatencyMs=(1, 100000),
                  blueLatencyMs=(1, 100000))
    for key, (low, high) in bounds.items():
        value = float(raw.get(key, DEFAULTS[key]))
        if not math.isfinite(value):
            raise ValueError("Invalid number: " + key)
        result[key] = max(low, value) if high is None else min(high, max(low, value))
    targets = raw.get("targets", [target("1.1.1.1", "Cloudflare"),
                                  target("8.8.8.8", "Google DNS")])
    if not isinstance(targets, list):
        raise ValueError("Targets must be an array")
    result["targets"] = []
    ids = set()
    for item in targets:
        if not isinstance(item, dict):
            raise ValueError("Invalid target")
        address = item.get("address", "")
        name = item.get("name", "")
        if not isinstance(address, str) or not isinstance(name, str):
            raise ValueError("Target name and address must be text")
        if not address.strip():
            continue
        entry = target(address.strip(), name.strip())
        identifier = str(item.get("id", entry["id"]))
        entry["id"] = identifier if identifier not in ids else entry["id"]
        ids.add(entry["id"])
        enabled = item.get("isEnabled", True)
        levels = item.get("notifyLevels", ["warning", "error"])
        if not isinstance(enabled, bool) or not isinstance(levels, list):
            raise ValueError("Invalid target options")
        entry["isEnabled"] = enabled
        entry["notifyLevels"] = [x for x in ("warning", "error") if x in levels]
        result["targets"].append(entry)
    return result


def config_path():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "pingstats/settings.json"


def load_settings(path=None):
    path = Path(path or config_path())
    return normalize(json.loads(path.read_text()) if path.exists() else {})


def save_settings(settings, path=None):
    path = Path(path or config_path())
    data = json.dumps(normalize(settings), ensure_ascii=False, indent=2) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".settings-")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(data)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@dataclass
class Sample:
    timestamp: float
    latency: float = None
    error: str = None

    @property
    def failed(self):
        return self.error is not None or self.latency is None


def evaluate(samples, green=60, blue=120):
    if sum(s.failed for s in samples[-5:]) >= 4:
        return "red"
    recent = samples[-10:]
    if any(s.failed for s in recent):
        return "orange"
    if len(recent) < 10:
        return "unknown"
    average = sum(s.latency for s in recent) / 10
    return "green" if average < green else "blue" if average < max(green, blue) else "yellow"


def should_notify(old, new, levels):
    if old == new or new == "unknown" or (old == "unknown" and new not in NORMAL):
        return False
    if old in NORMAL and new in NORMAL:
        return False
    source = old if new in NORMAL else new
    if source == "unknown":
        return bool(levels)
    return ("warning" if source == "yellow" else "error") in levels
