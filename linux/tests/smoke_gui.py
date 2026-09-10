"""Run in a graphical session; uses temporary settings and loopback only."""
import os
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

with tempfile.TemporaryDirectory(prefix="pingstats-smoke-") as directory:
    os.environ["XDG_CONFIG_HOME"] = directory
    from pingstats.core import normalize, save_settings, target
    from pingstats.app import App, Settings, GLib
    save_settings(normalize(dict(targets=[dict(target("127.0.0.1", "Loopback"), notifyLevels=[])])))
    app = App()
    app.set_application_id("dev.pingstats.smoke")
    failures = []

    def check():
        try:
            assert app.window.get_visible()
            assert app.indicator is not None
            monitor = next(iter(app.monitors.values()))
            assert monitor["samples"], "No probe completed"
            assert monitor["samples"][-1].error is None
            assert Path(app.indicator.get_icon()).is_file()
            dialog = Settings(app)
            dialog.show_all()
            assert dialog.collect() == app.settings
            dialog.destroy()
            app.hide_window()
            assert not app.window.get_visible()
            app.window.present()
            print("PASS: GTK window, chart, settings, indicator, loopback probe, hide/reopen")
        except Exception as error:
            failures.append(str(error))
        finally:
            app.quit()
        return False

    GLib.timeout_add(2500, check)
    app.run([])
    if failures:
        raise AssertionError(failures)
