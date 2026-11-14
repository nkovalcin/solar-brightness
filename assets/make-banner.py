#!/usr/bin/env python3
"""Draw assets/banner-dark.svg and assets/banner-light.svg.

One stylised equinox day at 48° N in a 16 second loop. The sun crosses the sky,
the monitor's screen follows the brightness curve of macos/solar-brightness, and
the readout prints the same line the log does. Every number comes from the
script itself, nothing is drawn by hand.

    python3 assets/make-banner.py
"""
import importlib.util
import math
import re
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_loader = SourceFileLoader("sb", str(ROOT / "macos" / "solar-brightness"))
_spec = importlib.util.spec_from_loader("sb", _loader)
sb = importlib.util.module_from_spec(_spec)
_loader.exec_module(sb)

W, H = 1200, 420
HORIZON = 246
PEAK = 42.0                     # equinox noon at 48° N
DUR = 16                        # seconds per day
STEPS = 96                      # 15 minute samples
X0, X1 = 70, 1130               # sun path from sunrise to sunset
AMP = 172                       # pixels for PEAK degrees
CURVE = sb.DEFAULTS["curves"]["internal"]

THEMES = {
    "dark": dict(
        night="#0B1330", day="#1E3A70", ground="#080D22", line="#36407A",
        sun="#FFB23F", ray="#FFB23F", text="#EEF1F8", muted="#8F98BD",
        bezel="#2A3263", screen="#FFE3A8", stars="#C9D2F2", path="#FFB23F"),
    "light": dict(
        night="#1B2550", day="#BFDDF6", ground="#F4F7FB", line="#C7D3E6",
        sun="#F29A12", ray="#F29A12", text="#0E1733", muted="#5A6585",
        bezel="#1B2550", screen="#FFF2D1", stars="#E6ECFF", path="#F29A12"),
}


def frames():
    """t in [0, 1): first half is the day (sunrise to sunset), second half the night."""
    out = []
    for i in range(STEPS + 1):
        t = i / STEPS
        elev = PEAK * math.sin(2 * math.pi * t)
        x = X0 + (X1 - X0) * (t * 2 if t <= 0.5 else (t - 0.5) * 2)
        if t > 0.5:          # at night the sun runs back under the ground, hidden
            x = X1 - (X1 - X0) * (t - 0.5) * 2
        y = HORIZON - AMP * elev / PEAK
        level = sb.level_for(elev, CURVE)
        clock = (6 * 60 + t * 24 * 60) % (24 * 60)
        out.append(dict(t=t, elev=elev, x=x, y=y, level=level, clock=clock))
    return out


def fmt(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")


def svg(theme):
    c = THEMES[theme]
    fr = frames()
    kt = ";".join(fmt(f["t"]) for f in fr)
    lo, hi = min(f["level"] for f in fr), max(f["level"] for f in fr)

    def norm(level):
        return (level - lo) / (hi - lo)

    sun_xy = ";".join(f"{fmt(f['x'])},{fmt(f['y'])}" for f in fr)
    day_op = ";".join(fmt(max(0.0, min(1.0, (f["elev"] + 6) / 24))) for f in fr)
    star_op = ";".join(fmt(max(0.0, min(1.0, (-f["elev"] - 2) / 10))) for f in fr)
    screen_op = ";".join(fmt(0.28 + 0.72 * norm(f["level"])) for f in fr)
    bar_w = ";".join(fmt(4 + 96 * f["level"] / 100) for f in fr)

    # readout: one line per hour, shown with discrete timing like the real log
    lines = []
    for hstep in range(24):
        a, b = hstep / 24, (hstep + 1) / 24
        f = fr[round(a * STEPS)]
        hh, mm = divmod(int(round(f["clock"])), 60)
        text = f"{hh:02d}:{mm:02d}  sun {f['elev']:6.1f}°  ->  built-in {f['level']}"
        if hstep == 0:
            anim = f'<animate attributeName="opacity" values="1;0" keyTimes="0;{fmt(b)}" dur="{DUR}s" calcMode="discrete" repeatCount="indefinite"/>'
        else:
            anim = f'<animate attributeName="opacity" values="0;1;0" keyTimes="0;{fmt(a)};{fmt(b)}" dur="{DUR}s" calcMode="discrete" repeatCount="indefinite"/>'
        lines.append(f'<text x="66" y="394" class="mono read" opacity="{1 if hstep == 0 else 0}" xml:space="preserve">{text}{anim}</text>')

    # the path the sun follows by day, dashed
    day_path = " ".join(f"{'M' if i == 0 else 'L'}{fmt(f['x'])},{fmt(f['y'])}"
                        for i, f in enumerate(fr) if f["t"] <= 0.5)

    stars = [(140, 52), (232, 120), (318, 40), (455, 92), (590, 30), (702, 108), (812, 58),
             (930, 34), (1012, 124), (1104, 70), (380, 176), (860, 170), (1160, 150), (60, 150)]
    star_svg = "".join(f'<circle cx="{x}" cy="{y}" r="{1.6 if i % 3 else 2.2}" fill="{c["stars"]}"/>'
                       for i, (x, y) in enumerate(stars))

    rays = "".join(
        f'<line x1="{fmt(26 * math.cos(a))}" y1="{fmt(26 * math.sin(a))}" '
        f'x2="{fmt(36 * math.cos(a))}" y2="{fmt(36 * math.sin(a))}"/>'
        for a in [k * math.pi / 4 for k in range(8)])

    mx, my = 936, 218           # monitor top left
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-labelledby="t d">
<title id="t">solar-brightness</title>
<desc id="d">The sun crosses the sky over one day while a monitor dims and brightens with it.</desc>
<style>
  .mono {{ font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace; }}
  .title {{ font-size: 46px; font-weight: 700; fill: {c["text"]}; letter-spacing: -0.5px; }}
  .tag {{ font-size: 21px; fill: {c["muted"]}; }}
  .read {{ font-size: 20px; font-weight: 600; fill: {c["sun"]}; }}
</style>
<defs>
  <clipPath id="sky"><rect width="{W}" height="{HORIZON}"/></clipPath>
  <radialGradient id="halo">
    <stop offset="0.3" stop-color="{c["sun"]}" stop-opacity="0.32"/>
    <stop offset="1" stop-color="{c["sun"]}" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="glow" cx="50%" cy="50%" r="50%">
    <stop offset="0" stop-color="{c["screen"]}" stop-opacity="0.55"/>
    <stop offset="1" stop-color="{c["screen"]}" stop-opacity="0"/>
  </radialGradient>
</defs>

<rect width="{W}" height="{HORIZON}" fill="{c["night"]}"/>
<rect width="{W}" height="{HORIZON}" fill="{c["day"]}">
  <animate attributeName="opacity" values="{day_op}" keyTimes="{kt}" dur="{DUR}s" repeatCount="indefinite"/>
</rect>
<g opacity="0">{star_svg}
  <animate attributeName="opacity" values="{star_op}" keyTimes="{kt}" dur="{DUR}s" repeatCount="indefinite"/>
</g>
<path d="{day_path}" fill="none" stroke="{c["path"]}" stroke-opacity="0.35" stroke-width="2" stroke-dasharray="2 9" stroke-linecap="round"/>

<g clip-path="url(#sky)">
  <g>
    <animateTransform attributeName="transform" type="translate" values="{sun_xy}" keyTimes="{kt}" dur="{DUR}s" repeatCount="indefinite"/>
    <circle r="64" fill="url(#halo)"/>
    <g stroke="{c["ray"]}" stroke-width="4" stroke-linecap="round">{rays}</g>
    <circle r="19" fill="{c["sun"]}"/>
  </g>
</g>

<rect y="{HORIZON}" width="{W}" height="{H - HORIZON}" fill="{c["ground"]}"/>
<line x1="0" y1="{HORIZON}" x2="{W}" y2="{HORIZON}" stroke="{c["line"]}" stroke-width="2"/>

<ellipse cx="{mx + 96}" cy="{my + 62}" rx="150" ry="96" fill="url(#glow)">
  <animate attributeName="opacity" values="{screen_op}" keyTimes="{kt}" dur="{DUR}s" repeatCount="indefinite"/>
</ellipse>
<rect x="{mx}" y="{my}" width="192" height="122" rx="10" fill="{c["bezel"]}"/>
<rect x="{mx + 9}" y="{my + 9}" width="174" height="98" rx="4" fill="{c["screen"]}">
  <animate attributeName="opacity" values="{screen_op}" keyTimes="{kt}" dur="{DUR}s" repeatCount="indefinite"/>
</rect>
<rect x="{mx + 46}" y="{my + 88}" height="6" rx="3" fill="{c["bezel"]}" opacity="0.55" width="50">
  <animate attributeName="width" values="{bar_w}" keyTimes="{kt}" dur="{DUR}s" repeatCount="indefinite"/>
</rect>
<rect x="{mx + 80}" y="{my + 122}" width="32" height="16" fill="{c["bezel"]}"/>
<rect x="{mx + 56}" y="{my + 136}" width="80" height="6" rx="3" fill="{c["bezel"]}"/>

<text x="64" y="318" class="mono title">solar-brightness</text>
<text x="66" y="352" class="mono tag">your screen dims and brightens with the sun</text>
{"".join(lines)}
</svg>
'''


STILL_AT = 4 / 24             # 10:00, for people who ask for reduced motion


def still(animated: str) -> str:
    """Freeze every animation at STILL_AT: same picture, no movement."""
    def pick(values, key_times, discrete):
        vals, keys = values.split(";"), [float(k) for k in key_times.split(";")]
        idx = max(i for i, k in enumerate(keys) if k <= STILL_AT + 1e-9)
        return vals[idx]

    def anim(m):
        attrs = dict(re.findall(r'(\w[\w-]*)="([^"]*)"', m.group(0)))
        value = pick(attrs["values"], attrs["keyTimes"], attrs.get("calcMode") == "discrete")
        if m.group(1) == "animateTransform":
            return (f'<animateTransform attributeName="transform" type="translate" values="{value}" '
                    f'dur="0.001s" fill="freeze"/>')
        return f'<set attributeName="{attrs["attributeName"]}" to="{value}"/>'

    return re.sub(r"<(animate|animateTransform) [^>]*/>", anim, animated)


if __name__ == "__main__":
    for theme in THEMES:
        animated = svg(theme)
        for name, text in [(f"banner-{theme}.svg", animated), (f"banner-{theme}-still.svg", still(animated))]:
            out = ROOT / "assets" / name
            out.write_text(text)
            print(out.name, len(text) // 1024, "KB")
