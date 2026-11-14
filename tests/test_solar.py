"""Tests for the macOS script. Run: python3 -m unittest discover tests"""
import importlib.util
import unittest
from datetime import datetime, timedelta, timezone
from importlib.machinery import SourceFileLoader
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent.parent
_loader = SourceFileLoader("solar_brightness", str(ROOT / "macos" / "solar-brightness"))
_spec = importlib.util.spec_from_loader("solar_brightness", _loader)
sb = importlib.util.module_from_spec(_spec)
_loader.exec_module(sb)


def solar_noon_elevation(day: datetime, lat: float, lon: float) -> float:
    return max(sb.solar_elevation(day + timedelta(minutes=m), lat, lon) for m in range(0, 1440, 2))


class SolarElevation(unittest.TestCase):
    def test_solstice_noon_matches_geometry(self):
        # At solar noon on a solstice the elevation is 90 - lat ± 23.44 degrees.
        for lat, lon in [(0.0, 0.0), (48.15, 17.11), (60.17, 24.94), (-33.87, 151.21)]:
            june = solar_noon_elevation(datetime(2026, 6, 21, tzinfo=timezone.utc), lat, lon)
            dec = solar_noon_elevation(datetime(2026, 12, 21, tzinfo=timezone.utc), lat, lon)
            # declination is +23.44 in June and -23.44 in December
            for elevation, decl in [(june, 23.44), (dec, -23.44)]:
                expected = 90 - abs(lat - decl)
                self.assertAlmostEqual(elevation, expected, delta=0.7, msg=f"lat {lat}, decl {decl}")

    def test_equinox_equator_noon_is_overhead(self):
        e = solar_noon_elevation(datetime(2026, 3, 20, tzinfo=timezone.utc), 0.0, 0.0)
        self.assertGreater(e, 88.5)

    def test_london_midsummer_sunrise_and_sunset(self):
        # Greenwich, 21 June 2026: sunrise 04:43, sunset 21:21 local time (BST).
        day = datetime(2026, 6, 21, tzinfo=ZoneInfo("Europe/London"))
        events = dict(sb.sun_events(day, 51.4769, -0.0005))
        self.assertLess(abs(events["sunrise"] - day.replace(hour=4, minute=43)), timedelta(minutes=3))
        self.assertLess(abs(events["sunset"] - day.replace(hour=21, minute=21)), timedelta(minutes=3))

    def test_time_zone_does_not_matter(self):
        utc = datetime(2026, 10, 25, 14, 30, tzinfo=timezone.utc)
        for zone in ["Europe/Bratislava", "America/New_York", "Asia/Tokyo"]:
            self.assertAlmostEqual(sb.solar_elevation(utc.astimezone(ZoneInfo(zone)), 48.15, 17.11),
                                   sb.solar_elevation(utc, 48.15, 17.11), places=9)


class Curve(unittest.TestCase):
    CURVE = [[25, 70], [8, 58], [0, 48], [-6, 42], [-12, 38]]

    def test_clamps_at_both_ends(self):
        self.assertEqual(sb.level_for(60, self.CURVE), 70)
        self.assertEqual(sb.level_for(-40, self.CURVE), 38)

    def test_hits_points_and_interpolates(self):
        self.assertEqual(sb.level_for(8, self.CURVE), 58)
        self.assertEqual(sb.level_for(4, self.CURVE), 53)
        self.assertEqual(sb.level_for(-3, self.CURVE), 45)

    def test_point_order_does_not_matter(self):
        self.assertEqual(sb.level_for(4, list(reversed(self.CURVE))), 53)

    def test_never_decreases_with_higher_sun(self):
        levels = [sb.level_for(e / 2, self.CURVE) for e in range(-60, 80)]
        self.assertEqual(levels, sorted(levels))


class DisplayList(unittest.TestCase):
    def test_skips_builtin_and_reads_names(self):
        text = ("[1] (null) (37D8832A-2D66-02CA-B9F7-8F30A301B230)\n"
                "[2] VP2756-2K (32CC8B47-B592-465F-9DDB-194D82105A87)\n"
                "[3] P27h-20 (11111111-2222-3333-4444-555555555555)\n")
        self.assertEqual(sb.parse_m1ddc_list(text), [("2", "VP2756-2K"), ("3", "P27h-20")])

    def test_empty_list(self):
        self.assertEqual(sb.parse_m1ddc_list(""), [])


class Config(unittest.TestCase):
    def test_example_config_has_only_known_keys(self):
        import json
        example = json.loads((ROOT / "config.example.json").read_text())
        self.assertLessEqual(set(example), set(sb.DEFAULTS))


if __name__ == "__main__":
    unittest.main()
