import hashlib
import math
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gio, GLib, Gtk, Gdk, Pango, PangoCairo

from .core import (DEFAULTS, NORMAL, Sample, evaluate, load_settings, normalize, save_settings,
                   should_notify, sparkline, target)
from .desktop import APP_ID, autostart_path, set_autostart
from .i18n import tr, error_text
from .probe import local_addresses, probe

COLORS = dict(green="#34c759", blue="#007aff", yellow="#e8be00", orange="#ff9500", red="#ff3b30", unknown="#8e8e93")
GLYPHS = dict(green="🟢", blue="🔵", yellow="🟡", orange="🟠", red="🔴", unknown="⚪")
TITLES = dict(green="Good", blue="Normal", yellow="Warning", orange="Error", red="Critical", unknown="Unknown")
FIELDS = list(zip(DEFAULTS, ("Background interval (s)", "Background timeout (s)",
                           "Foreground interval (s)", "Foreground timeout (s)",
                           "Chart window (s)", "Green threshold (ms)", "Blue threshold (ms)")))


def button(label, callback):
    widget = Gtk.Button(label=tr(label))
    widget.connect("clicked", callback)
    return widget


def message(parent, text):
    dialog = Gtk.MessageDialog(transient_for=parent, modal=True, message_type=Gtk.MessageType.ERROR,
                               buttons=Gtk.ButtonsType.NONE, text=error_text(text))
    dialog.add_button(tr("Close"), Gtk.ResponseType.CLOSE)
    dialog.run()
    dialog.destroy()


def deliver(future, callback, *args):
    if not future.cancelled():
        GLib.idle_add(callback, *args, future.result())


class Settings(Gtk.Dialog):
    def __init__(self, app):
        super().__init__(title=tr("Settings"), transient_for=app.window, modal=True)
        self.app = app
        self.set_default_size(800, 600)
        self.add_button(tr("Cancel"), Gtk.ResponseType.CANCEL)
        self.add_button(tr("Save"), Gtk.ResponseType.OK)
        self.rows = []
        box = self.get_content_area()
        box.set_spacing(8)
        box.set_border_width(12)
        scroller = Gtk.ScrolledWindow()
        scroller.set_vexpand(True)
        self.targets = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        scroller.add(self.targets)
        box.pack_start(scroller, True, True, 0)
        box.pack_start(button("Add target", lambda _: self.add_target(target(""))), False, False, 0)
        grid = Gtk.Grid(column_spacing=16, row_spacing=5)
        self.values = {}
        for index, (key, label) in enumerate(FIELDS):
            spin = Gtk.SpinButton.new_with_range(.1, 100000, .1)
            spin.set_digits(1)
            self.values[key] = spin
            grid.attach(Gtk.Label(label=tr(label), xalign=0), 0, index, 1, 1)
            grid.attach(spin, 1, index, 1, 1)
        box.pack_start(grid, False, False, 0)
        startup = Gtk.CheckButton(label=tr("Launch at login"))
        startup.set_active(autostart_path().exists())
        startup.connect("toggled", self.autostart_changed)
        box.pack_start(startup, False, False, 0)
        actions = Gtk.Box(spacing=8)
        actions.pack_start(button("Import JSON", lambda _: self.transfer(False)), False, False, 0)
        actions.pack_start(button("Export JSON", lambda _: self.transfer(True)), False, False, 0)
        box.pack_start(actions, False, False, 0)
        self.populate(app.settings)

    def autostart_changed(self, widget):
        try:
            set_autostart(widget.get_active())
        except (OSError, ValueError) as error:
            widget.handler_block_by_func(self.autostart_changed)
            widget.set_active(autostart_path().exists())
            widget.handler_unblock_by_func(self.autostart_changed)
            message(self, error)

    def populate(self, settings):
        for child in self.targets.get_children():
            child.destroy()
        self.rows = []
        for item in settings["targets"]:
            self.add_target(item)
        for key, widget in self.values.items():
            widget.set_value(settings[key])

    def add_target(self, item):
        row = Gtk.Box(spacing=6)
        enabled = Gtk.CheckButton(label=tr("Enabled"))
        enabled.set_active(item["isEnabled"])
        name = Gtk.Entry(text=item["name"], placeholder_text=tr("Name"))
        address = Gtk.Entry(text=item["address"], placeholder_text=tr("Address"))
        warning = Gtk.CheckButton(label=tr("Warning"))
        warning.set_active("warning" in item["notifyLevels"])
        error = Gtk.CheckButton(label=tr("Error"))
        error.set_active("error" in item["notifyLevels"])
        entry = (item["id"], row, enabled, name, address, warning, error)
        self.rows.append(entry)
        def remove(_):
            self.rows.remove(entry)
            row.destroy()
        for widget in (enabled, name, address, warning, error, button("Remove", remove)):
            row.pack_start(widget, widget is address, widget is address, 0)
        self.targets.pack_start(row, False, False, 0)
        row.show_all()

    def collect(self):
        settings = {key: widget.get_value() for key, widget in self.values.items()}
        settings["targets"] = [dict(id=i, name=n.get_text(), address=a.get_text(), isEnabled=e.get_active(),
                                    notifyLevels=[level for level, check in (("warning", w), ("error", r)) if check.get_active()])
                               for i, _, e, n, a, w, r in self.rows]
        return normalize(settings)

    def transfer(self, export):
        dialog = Gtk.FileChooserDialog(title=tr("Export JSON" if export else "Import JSON"), transient_for=self,
                                       action=Gtk.FileChooserAction.SAVE if export else Gtk.FileChooserAction.OPEN)
        dialog.add_buttons(tr("Cancel"), Gtk.ResponseType.CANCEL, tr("Save" if export else "Import JSON"), Gtk.ResponseType.OK)
        if export:
            dialog.set_current_name("pingstats-settings.json")
            dialog.set_do_overwrite_confirmation(True)
        if dialog.run() == Gtk.ResponseType.OK:
            try:
                if export:
                    save_settings(self.collect(), dialog.get_filename())
                else:
                    self.populate(load_settings(dialog.get_filename()))
            except (OSError, ValueError, TypeError) as error:
                message(self, error)
        dialog.destroy()


class Overview(Gtk.Window):
    """Compact chart layer opened from the tray, mirroring the macOS popover."""

    def __init__(self, app):
        super().__init__(title="PingStats")
        self.app = app
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_type_hint(Gdk.WindowTypeHint.UTILITY)
        frame = Gtk.Frame(shadow_type=Gtk.ShadowType.OUT)
        self.rows = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=12)
        frame.add(self.rows)
        self.add(frame)
        self.connect("delete-event", lambda *_: self.hide_on_delete())
        self.connect("focus-out-event", lambda *_: self.hide_on_delete())
        self.connect("key-press-event", lambda _, event: event.keyval == Gdk.KEY_Escape and self.hide_on_delete())

    def rebuild(self):
        for child in self.rows.get_children():
            child.destroy()
        for monitor in self.app.monitors.values():
            summary = Gtk.Label(xalign=0)
            chart = Gtk.DrawingArea()
            chart.set_size_request(280, 60)
            chart.connect("draw", self.app.draw_chart, monitor, True)
            monitor["summary"], monitor["mini"] = summary, chart
            self.rows.pack_start(summary, False, False, 0)
            self.rows.pack_start(chart, False, False, 0)
            self.app.render_monitor(monitor)
        if not self.app.monitors:
            self.rows.pack_start(Gtk.Label(label=tr("No targets. Add one in Settings.")), False, False, 0)
        self.rows.pack_start(Gtk.Label(label=tr("Close chart") + " (Esc)"), False, False, 0)
        self.rows.show_all()

    def toggle(self):
        if self.get_visible():
            self.hide()
            return
        self.rebuild()
        self.show_all()
        # GNOME hands the tray no position, so anchor under the panel on the icon side.
        area = (Gdk.Display.get_default().get_primary_monitor() or
                Gdk.Display.get_default().get_monitor(0)).get_workarea()
        size = self.get_preferred_size()[1]
        self.move(area.x + max(0, area.width - size.width - 12), area.y + 12)
        self.present()
        self.app.next_probe = 0


class App(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.window = None
        self.executor = ThreadPoolExecutor(max_workers=16)
        self.monitors = {}
        self.next_probe = 0
        self.next_addresses = 0
        self.address_pending = False
        self.stopping = False
        self.icons = tempfile.TemporaryDirectory(prefix="pingstats-icons-")
        self.icon_state = None
        self.indicator = None
        self.menu = None
        self.overview = None

    def do_activate(self):
        if self.window:
            self.window.present()
            return
        try:
            self.settings = load_settings()
        except (OSError, ValueError, TypeError) as error:
            message(None, tr("Settings could not be loaded") + "\n" + error_text(error))
            self.quit()
            return
        self.hold()
        self.window = Gtk.ApplicationWindow(application=self, title="PingStats")
        self.window.set_default_size(780, 560)
        self.window.connect("delete-event", self.hide_window)
        self.window.connect("notify::visible", lambda *_: setattr(self, "next_probe", 0))
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=12)
        self.window.add(box)
        toolbar = Gtk.Box(spacing=8)
        self.clock = Gtk.Label(xalign=0)
        toolbar.pack_start(self.clock, True, True, 0)
        toolbar.pack_start(button("Check now", lambda _: self.tick(force=True)), False, False, 0)
        toolbar.pack_start(button("Settings", lambda _: self.show_settings()), False, False, 0)
        toolbar.pack_start(button("Quit", lambda _: self.quit()), False, False, 0)
        box.pack_start(toolbar, False, False, 0)
        self.ip_box = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE)
        box.pack_start(self.ip_box, False, False, 0)
        scroller = Gtk.ScrolledWindow()
        self.grid = Gtk.Grid(column_spacing=12, row_spacing=12, column_homogeneous=True)
        scroller.add(self.grid)
        box.pack_start(scroller, True, True, 0)
        box.pack_start(Gtk.Label(label=tr("Monitoring continues when this window is closed.")), False, False, 0)
        box.pack_start(Gtk.Label(label=tr("Tray support requires the GNOME AppIndicator extension.")), False, False, 0)
        self.overview = Overview(self)
        self.reconcile()
        self.setup_indicator()
        self.window.show_all()
        self.tick()
        self.timer = GLib.timeout_add(250, self.tick)

    def hide_window(self, *_):
        self.window.hide()
        return True

    def setup_indicator(self):
        for namespace in ("AppIndicator3", "AyatanaAppIndicator3"):
            try:
                gi.require_version(namespace, "0.1")
                from importlib import import_module
                api = import_module("gi.repository." + namespace)
                self.indicator = api.Indicator.new(APP_ID, "network-transmit-receive", api.IndicatorCategory.APPLICATION_STATUS)
                self.indicator.set_status(api.IndicatorStatus.ACTIVE)
                break
            except (ValueError, ImportError):
                continue
        if self.indicator:
            self.menu = Gtk.Menu()
            self.indicator.set_menu(self.menu)
            self.build_menu()
            self.update_indicator()

    def build_menu(self):
        """The tray menu is the only surface a left click can open under GNOME,
        so each target reports its state there as a text chart."""
        if not self.menu:
            return
        for child in self.menu.get_children():
            child.destroy()
        for monitor in self.monitors.values():
            item = Gtk.MenuItem(label="")
            item.connect("activate", lambda _: self.overview.toggle())
            monitor["item"] = item
            self.render_monitor(monitor)
            self.menu.append(item)
        if not self.monitors:
            self.menu.append(Gtk.MenuItem(label=tr("No targets. Add one in Settings.")))
        self.menu.append(Gtk.SeparatorMenuItem())
        for label, callback in (("Chart", lambda _: self.overview.toggle()),
                                ("Monitor", lambda _: self.window.present()),
                                ("Settings", lambda _: self.show_settings()), ("Quit", lambda _: self.quit())):
            item = Gtk.MenuItem(label=tr(label))
            item.connect("activate", callback)
            self.menu.append(item)
        self.menu.show_all()

    def reconcile(self):
        previous = self.monitors
        self.monitors = {}
        for child in self.grid.get_children():
            child.destroy()
        for item in self.settings["targets"]:
            if not item["isEnabled"]:
                continue
            monitor = previous.get(item["id"])
            if not monitor or monitor["target"]["address"] != item["address"]:
                monitor = dict(samples=[], health="unknown", pending=False)
            monitor["target"] = item
            monitor["item"] = monitor["summary"] = monitor["mini"] = None
            self.monitors[item["id"]] = monitor
            frame = Gtk.Frame(label=item["name"] or item["address"])
            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, margin=8)
            frame.add(content)
            content.pack_start(Gtk.Label(label=item["address"], selectable=True), False, False, 0)
            label = Gtk.Label()
            monitor["label"] = label
            content.pack_start(label, False, False, 0)
            chart = Gtk.DrawingArea()
            chart.set_size_request(300, 140)
            chart.connect("draw", self.draw_chart, monitor)
            monitor["chart"] = chart
            content.pack_start(chart, True, True, 0)
            index = len(self.monitors) - 1
            self.grid.attach(frame, index % 2, index // 2, 1, 1)
            self.render_monitor(monitor)
        if not self.monitors:
            self.grid.attach(Gtk.Label(label=tr("No targets. Add one in Settings.")), 0, 0, 2, 1)
        self.grid.show_all()
        self.build_menu()
        if self.overview.get_visible():
            self.overview.rebuild()

    def show_settings(self):
        self.window.present()
        dialog = Settings(self)
        dialog.show_all()
        while dialog.run() == Gtk.ResponseType.OK:
            try:
                settings = dialog.collect()
                save_settings(settings)
                self.settings = settings
                self.reconcile()
                self.update_indicator()
                self.next_probe = 0
                break
            except (OSError, ValueError, TypeError) as error:
                message(dialog, error)
        dialog.destroy()

    def tick(self, force=False):
        if self.stopping:
            return False
        self.clock.set_text(time.strftime("%H:%M:%S"))
        now = time.monotonic()
        if now >= self.next_addresses and not self.address_pending:
            self.next_addresses = now + 5
            self.address_pending = True
            future = self.executor.submit(local_addresses)
            future.add_done_callback(lambda f: deliver(f, self.addresses_done))
        if force or now >= self.next_probe:
            mode = "foreground" if self.visible() else "background"
            self.next_probe = now + self.settings[mode + "Interval"]
            for monitor in self.monitors.values():
                if monitor["pending"]:
                    continue
                monitor["pending"] = True
                future = self.executor.submit(probe, monitor["target"]["address"], self.settings[mode + "Timeout"])
                future.add_done_callback(lambda f, m=monitor: deliver(f, self.probe_done, m))
        if self.visible():
            for monitor in self.monitors.values():
                self.redraw(monitor)
        return True

    def visible(self):
        return self.window.get_visible() or self.overview.get_visible()

    def redraw(self, monitor):
        for key in ("chart", "mini"):
            if monitor.get(key):
                monitor[key].queue_draw()

    def addresses_done(self, addresses):
        self.address_pending = False
        if self.stopping or addresses == getattr(self, "addresses", None):
            return False
        self.addresses = addresses
        for child in self.ip_box.get_children():
            child.destroy()
        for name, address in addresses:
            def copy(widget, value=address):
                Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(value, -1)
                widget.set_tooltip_text(tr("Copied"))
            self.ip_box.add(button(tr("Local IP") + " · " + name + " " + address, copy))
        self.ip_box.show_all()
        return False

    def probe_done(self, monitor, result):
        monitor["pending"] = False
        if self.stopping or self.monitors.get(monitor["target"]["id"]) is not monitor:
            return False
        now = time.time()
        samples = monitor["samples"]
        samples.append(Sample(now, *result))
        samples[:] = [s for s in samples if s.timestamp >= now - self.settings["chartWindowSeconds"]]
        old = monitor["health"]
        new = evaluate(samples, self.settings["greenLatencyMs"], self.settings["blueLatencyMs"])
        monitor["health"] = new
        item = monitor["target"]
        if should_notify(old, new, item["notifyLevels"]):
            title = "PingStats: " + (item["name"] or item["address"])
            if old not in NORMAL and old != "unknown" and new in NORMAL:
                title += " · " + tr("Recovered")
            notification = Gio.Notification.new(title)
            notification.set_body(tr(TITLES[old]) + " → " + tr(TITLES[new]))
            notification.set_icon(Gio.ThemedIcon.new("network-transmit-receive"))
            self.send_notification(item["id"], notification)
        self.render_monitor(monitor)
        self.update_indicator()
        return False

    def render_monitor(self, monitor):
        samples = monitor["samples"]
        health, item = monitor["health"], monitor["target"]
        title = item["name"] or item["address"]
        latest = "—" if not samples or samples[-1].latency is None else "%.0f ms" % samples[-1].latency
        values = [s.latency for s in samples[-10:] if s.latency is not None]
        average = "%.0f ms" % (sum(values) / len(values)) if values else "—"
        state = '<span foreground="%s">● %s</span>  %s: %s · %s: %s' % (
            COLORS[health], tr(TITLES[health]), tr("Latest"), latest, tr("Average (10)"), average)
        error = error_text(samples[-1].error) if samples and samples[-1].error else None
        for widget, markup in ((monitor["label"], state),
                               (monitor["summary"], "<b>%s</b>\n%s" % (GLib.markup_escape_text(title), state))):
            if widget:
                widget.set_markup(markup)
                widget.set_tooltip_text(error)
        if monitor["item"]:
            monitor["item"].set_label("%s %s  %s  %s · %s %s" % (
                GLYPHS[health], title, sparkline(samples, self.settings["blueLatencyMs"]),
                latest, tr("Average"), average))
        self.redraw(monitor)

    def draw_chart(self, widget, context, monitor, compact=False):
        width, height = widget.get_allocated_width(), widget.get_allocated_height()
        left, top, right, bottom = (4, 6, width - 4, height - 4) if compact else (45, 20, width - 8, height - 22)
        context.set_source_rgb(.5, .5, .5)
        context.set_line_width(1)
        context.move_to(left, top)
        context.line_to(left, bottom)
        context.line_to(right, bottom)
        context.stroke()
        samples = monitor["samples"]
        ceiling = max([100] + [s.latency for s in samples if s.latency is not None]) * 1.1
        def caption(text, x, y):
            layout = PangoCairo.create_layout(context)
            layout.set_font_description(Pango.FontDescription("Sans 8"))
            layout.set_text(text, -1)
            context.move_to(x, y)
            PangoCairo.show_layout(context, layout)
        if not compact:
            caption("%.0f ms" % ceiling, 1, top - 14)
            caption(tr("-%g min") % (self.settings["chartWindowSeconds"] / 60), left, height - 17)
            caption(time.strftime("%H:%M:%S"), right - 50, height - 17)
        cutoff = time.time() - self.settings["chartWindowSeconds"]
        connected = False
        for sample in samples:
            x = left + (sample.timestamp - cutoff) / self.settings["chartWindowSeconds"] * (right - left)
            if x < left:
                continue
            if sample.failed:
                context.stroke()
                context.set_source_rgb(1, .23, .19)
                context.rectangle(x - 1, bottom - 8, 2, 8)
                context.fill()
                connected = False
            else:
                context.set_source_rgb(.0, .48, 1)
                y = bottom - sample.latency / ceiling * (bottom - top)
                if connected:
                    context.line_to(x, y)
                else:
                    context.move_to(x, y)
                connected = True
        context.stroke()
        for sample in samples:
            if compact or sample.failed or sample.timestamp < cutoff:
                continue
            x = left + (sample.timestamp - cutoff) / self.settings["chartWindowSeconds"] * (right - left)
            y = bottom - sample.latency / ceiling * (bottom - top)
            context.set_source_rgb(.0, .48, 1)
            context.arc(x, y, 1.5, 0, 2 * math.pi)
            context.fill()
        return False

    def update_indicator(self):
        if not self.indicator:
            return
        state = tuple(m["health"] for m in self.monitors.values()) or ("unknown",)
        if state == self.icon_state:
            return
        rows = 2 if len(state) >= 10 else 1
        columns = math.ceil(len(state) / rows)
        pitch = min(7, 22 / columns)
        start = (24 - columns * pitch) / 2
        bars = []
        for index, health in enumerate(state):
            x, y = start + index % columns * pitch, 2 + index // columns * 10
            bars.append('<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>' %
                        (x, y, max(.2, pitch - 1), 9 if rows == 2 else 20, COLORS[health]))
        svg = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">' + "".join(bars) + '</svg>'
        # GNOME caches icons by path. Never replace an image at a published path;
        # identical content can safely reuse its cached image on later transitions.
        digest = hashlib.sha256(svg.encode("utf-8")).hexdigest()
        path = Path(self.icons.name) / ("status-%s.svg" % digest)
        if not path.exists():
            path.write_text(svg, encoding="utf-8")
        self.indicator.set_icon_full(str(path), "PingStats")
        self.icon_state = state

    def do_shutdown(self):
        self.stopping = True
        self.executor.shutdown(wait=False, cancel_futures=True)
        self.icons.cleanup()
        Gtk.Application.do_shutdown(self)


def main():
    return App().run(sys.argv)
