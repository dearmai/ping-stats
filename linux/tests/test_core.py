import json
from pathlib import Path
import tempfile
import unittest

from pingstats.core import Sample, evaluate, load_settings, normalize, save_settings, should_notify, sparkline


class CoreTests(unittest.TestCase):
    def test_shared_health_cases(self):
        cases = json.loads((Path(__file__).resolve().parents[2] / "shared/health-cases.json").read_text())
        for case in cases:
            with self.subTest(case["name"]):
                samples = [Sample(i, latency) for i, latency in enumerate(case["latencies"])]
                self.assertEqual(evaluate(samples, case.get("green", 60), case.get("blue", 120)), case["expected"])

    def test_error_message_overrides_latency(self):
        self.assertEqual(evaluate([Sample(0, 10, "failure")]), "orange")

    def test_all_notification_transitions(self):
        # Explicit expected matrix copied from the documented Swift behavior.
        states = ["unknown", "green", "blue", "yellow", "orange", "red"]
        expected = {
            "unknown": {"green", "blue"},
            "green": {"yellow", "orange", "red"},
            "blue": {"yellow", "orange", "red"},
            "yellow": {"green", "blue", "orange", "red"},
            "orange": {"green", "blue", "yellow", "red"},
            "red": {"green", "blue", "yellow", "orange"},
        }
        for old in states:
            for new in states:
                self.assertEqual(should_notify(old, new, ["warning", "error"]), new in expected[old], (old, new))
                self.assertFalse(should_notify(old, new, []))

    def test_notification_level_filter(self):
        self.assertFalse(should_notify("orange", "green", ["warning"]))
        self.assertTrue(should_notify("yellow", "green", ["warning"]))
        self.assertTrue(should_notify("red", "blue", ["error"]))
        self.assertFalse(should_notify("green", "yellow", ["error"]))
        self.assertTrue(should_notify("unknown", "green", ["error"]))

    def test_sparkline_scales_against_the_blue_threshold(self):
        samples = [Sample(0, 10), Sample(1, 60), Sample(2, 120), Sample(3, None, "down")]
        self.assertEqual(sparkline(samples, 120), "▃▆█×")
        # A spike above the threshold stretches the scale, so normal latency flattens.
        self.assertEqual(sparkline(samples + [Sample(4, 1200)], 120), "▁▂▃×█")
        self.assertEqual(sparkline(samples, 120, width=2), "█×")
        self.assertEqual(sparkline([], 120), "")

    def test_settings_roundtrip_and_bounds(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            settings = normalize(dict(backgroundInterval=-3, chartWindowSeconds=9000,
                                      targets=[dict(name=" Local ", address=" 127.0.0.1 "), dict(address=" ")]))
            save_settings(settings, path)
            self.assertEqual(load_settings(path), settings)
            self.assertEqual(settings["backgroundInterval"], 1)
            self.assertEqual(settings["chartWindowSeconds"], 3600)
            self.assertEqual(settings["targets"][0]["name"], "Local")
            self.assertEqual(len(settings["targets"]), 1)

    def test_invalid_settings_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            path.write_text("broken")
            with self.assertRaises(ValueError):
                load_settings(path)
            self.assertEqual(path.read_text(), "broken")
        for value in (float("nan"), float("inf")):
            with self.assertRaises(ValueError):
                normalize(dict(greenLatencyMs=value))


if __name__ == "__main__":
    unittest.main()
