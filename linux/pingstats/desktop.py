"""XDG desktop entry and opt-in session autostart."""
import os
from pathlib import Path

APP_ID = "dev.pingstats.app"


def data_home():
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))


def autostart_path():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / ("autostart/" + APP_ID + ".desktop")


def desktop_entry(launcher):
    # Desktop Exec uses its own quoting, followed by desktop-entry unescaping.
    escaped = str(launcher).replace("%", "%%")
    for character in ("\\", '"', "`", "$"):
        escaped = escaped.replace(character, "\\" + character)
    escaped = escaped.replace("\\", "\\\\")
    return ('[Desktop Entry]\nType=Application\nName=PingStats\n'
            'Comment=Network latency monitor\nExec="' + escaped + '"\n'
            'Icon=network-transmit-receive\nTerminal=false\nCategories=Network;Monitor;\n'
            'StartupNotify=true\nX-GNOME-UsesNotifications=true\n')


def set_autostart(enabled):
    path = autostart_path()
    if enabled:
        launcher = data_home() / "pingstats/pingstats-linux"
        if not launcher.is_file():
            raise ValueError("Install PingStats before enabling autostart")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(desktop_entry(launcher))
    else:
        path.unlink(missing_ok=True)
