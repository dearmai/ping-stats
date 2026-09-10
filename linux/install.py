#!/usr/bin/python3
"""Install for the current user without root or pip."""
import shutil
from pathlib import Path

from pingstats.desktop import APP_ID, data_home, desktop_entry

source = Path(__file__).resolve().parent
destination = data_home() / "pingstats"
destination.mkdir(parents=True, exist_ok=True)
shutil.copytree(source / "pingstats", destination / "pingstats", dirs_exist_ok=True,
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
launcher = destination / "pingstats-linux"
shutil.copy2(source / "pingstats-linux", launcher)
launcher.chmod(0o755)
applications = data_home() / "applications"
applications.mkdir(parents=True, exist_ok=True)
(applications / (APP_ID + ".desktop")).write_text(desktop_entry(launcher))
print("Installed:", launcher)
