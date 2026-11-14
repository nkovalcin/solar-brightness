"""The Windows script must compute the same sun as the macOS script.

Runs only where PowerShell is available (the Windows CI job):
    python -m unittest tests.test_parity
"""
import shutil
import subprocess
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from test_solar import sb  # noqa: F401  (loads the macOS script as a module)

ROOT = Path(__file__).resolve().parent.parent
PS = shutil.which("pwsh") or shutil.which("powershell")


@unittest.skipUnless(PS, "PowerShell not installed")
class Parity(unittest.TestCase):
    def elevation_ps(self, when: datetime, lat: float, lon: float) -> float:
        out = subprocess.run(
            [PS, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "windows" / "solar-brightness.ps1"),
             "-ElevationAt", when.strftime("%Y-%m-%dT%H:%M:%SZ"), "-Lat", str(lat), "-Lon", str(lon)],
            capture_output=True, text=True, check=True)
        return float(out.stdout.strip())

    def test_same_elevation(self):
        start = datetime(2026, 1, 1, tzinfo=timezone.utc)
        for i, (lat, lon) in enumerate([(48.15, 17.11), (-33.87, 151.21), (64.13, -21.9), (0.0, 0.0)]):
            for k in range(6):
                when = start + timedelta(days=61 * k + i, hours=4 * k + i)
                with self.subTest(lat=lat, lon=lon, when=when):
                    self.assertAlmostEqual(self.elevation_ps(when, lat, lon), sb.solar_elevation(when, lat, lon), places=6)


if __name__ == "__main__":
    unittest.main()
