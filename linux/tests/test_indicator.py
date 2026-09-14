"""Exercise the tray icon and the text chart the tray menu shows on a click."""
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from xml.etree import ElementTree

from pingstats.app import App, COLORS, GLYPHS
from pingstats.core import Sample
from pingstats.i18n import tr


class CachedIndicator:
    def __init__(self):
        self.cache = {}
        self.calls = []

    def set_icon_full(self, path, description):
        self.calls.append(path)
        if path not in self.cache:
            self.cache[path] = Path(path).read_text()
        self.displayed = self.cache[path]


class IndicatorTests(unittest.TestCase):
    def test_cached_tray_tracks_startup_failure_and_recovery(self):
        with tempfile.TemporaryDirectory() as directory:
            indicator = CachedIndicator()
            app = SimpleNamespace(indicator=indicator, icon_state=None,
                                  icons=SimpleNamespace(name=directory), monitors={})
            states = [
                ("unknown", "unknown", "unknown", "unknown", "unknown"),
                ("green", "unknown", "unknown", "unknown", "unknown"),
                ("green", "green", "green", "red", "green"),
                ("green", "orange", "green", "red", "green"),
                ("green", "green", "green", "red", "green"),
                ("blue", "yellow", "green", "red", "green"),
                ("green",) * 5,
                ("green",) * 10,
                (),
            ]
            for state in states:
                with self.subTest(state=state):
                    app.monitors = {i: {"health": health} for i, health in enumerate(state)}
                    App.update_indicator(app)
                    rects = ElementTree.fromstring(indicator.displayed)
                    self.assertEqual([r.attrib["fill"] for r in rects],
                                     [COLORS[h] for h in state or ("unknown",)])
                    calls = len(indicator.calls)
                    App.update_indicator(app)
                    self.assertEqual(len(indicator.calls), calls)
                    for path, contents in indicator.cache.items():
                        self.assertEqual(Path(path).read_text(), contents)
            self.assertEqual(indicator.calls[2], indicator.calls[4])
            self.assertEqual(len(list(Path(directory).iterdir())), len(set(states)))


class Widget:
    """Stands in for the window label, the popover label and the tray menu item."""

    def __init__(self):
        self.markup = self.label = self.tooltip = None

    def set_markup(self, text):
        self.markup = text

    def set_label(self, text):
        self.label = text

    def set_tooltip_text(self, text):
        self.tooltip = text


class MenuTests(unittest.TestCase):
    def render(self, samples, health="green"):
        app = SimpleNamespace(settings=dict(blueLatencyMs=120), redraw=lambda monitor: None)
        monitor = dict(samples=samples, health=health, target=dict(name="Cloudflare", address="1.1.1.1"),
                       label=Widget(), summary=Widget(), item=Widget())
        App.render_monitor(app, monitor)
        return monitor

    def test_menu_item_carries_state_chart_and_latency(self):
        monitor = self.render([Sample(0, 10), Sample(1, 120), Sample(2, 20)])
        self.assertEqual(monitor["item"].label, GLYPHS["green"] + " Cloudflare  ▃█▄  20 ms · " + tr("Average") + " 50 ms")
        self.assertIn("Cloudflare", monitor["summary"].markup)
        self.assertIn(COLORS["green"], monitor["label"].markup)
        self.assertIsNone(monitor["label"].tooltip)

    def test_failures_reach_the_chart_and_the_tooltip(self):
        monitor = self.render([Sample(0, 10), Sample(1, None, "Timeout")], health="red")
        self.assertEqual(monitor["item"].label, GLYPHS["red"] + " Cloudflare  ▃×  — · " + tr("Average") + " 10 ms")
        self.assertEqual(monitor["summary"].tooltip, tr("Timeout"))

    def test_hidden_popover_and_missing_tray_are_skipped(self):
        monitor = dict(samples=[], health="unknown", target=dict(name="", address="1.1.1.1"),
                       label=Widget(), summary=None, item=None)
        App.render_monitor(SimpleNamespace(settings=dict(blueLatencyMs=120), redraw=lambda m: None), monitor)
        self.assertIn(tr("Unknown"), monitor["label"].markup)
