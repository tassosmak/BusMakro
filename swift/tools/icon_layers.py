"""Draws the two foreground layers of the BusMakro icon as 1024 x 1024 SVGs:
roads.svg  - central Athens' roads (every bus line's route), white on transparent, busier = thicker
bus.svg    - a bus seen from the front, windows and lights cut out so the background shows through
"""
import glob, json, math, sys
from collections import Counter

routes, out = sys.argv[1], sys.argv[2]
S = 1024
C_LAT, C_LON, HALF_KM = 37.9800, 23.7330, 4.2   # around Syntagma / Omonia, about 8 km across
k = math.cos(math.radians(C_LAT))

def px(lat, lon):
    x = (lon - C_LON) * 111.32 * k / HALF_KM
    y = (C_LAT - lat) * 111.32 / HALF_KM
    return ((x + 1) * S / 2, (y + 1) * S / 2)

Q = 3.0  # px: snap points so lines sharing a road share segments
count = Counter()
for f in glob.glob(f"{routes}/line_*.json"):
    d = json.load(open(f))
    for v in d.get("variants", {}).values():
        pts = [px(a, b) for a, b in v.get("shape", [])]
        pts = [(round(x / Q) * Q, round(y / Q) * Q) for x, y in pts]
        for a, b in zip(pts, pts[1:]):
            if a == b: continue
            if not any(-60 <= c <= S + 60 for c in (a[0], b[0])) or not any(-60 <= c <= S + 60 for c in (a[1], b[1])): continue
            count[tuple(sorted((a, b)))] += 1

def width(n):
    return 4 + 7 * min(1.0, math.log(n) / math.log(30))  # one line 4 px .. 30+ lines 11 px

buckets = {}
for seg, n in count.items():
    w = round(width(n))
    buckets.setdefault(w, []).append(seg)
paths = []
for w in sorted(buckets):
    d = "".join(f"M{a[0]:.0f} {a[1]:.0f}L{b[0]:.0f} {b[1]:.0f}" for a, b in buckets[w])
    paths.append(f'<path d="{d}" stroke-width="{w}"/>')
open(f"{out}/roads.svg", "w").write(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">'
    f'<g fill="none" stroke="#FFFFFF" stroke-linecap="round" stroke-linejoin="round">{"".join(paths)}</g></svg>')
print(len(count), "segments")

def rr(x, y, w, h, r):  # rounded rectangle as a path
    return (f"M{x+r} {y}H{x+w-r}A{r} {r} 0 0 1 {x+w} {y+r}V{y+h-r}A{r} {r} 0 0 1 {x+w-r} {y+h}"
            f"H{x+r}A{r} {r} 0 0 1 {x} {y+h-r}V{y+r}A{r} {r} 0 0 1 {x+r} {y}Z")

def circle(cx, cy, r):
    return f"M{cx-r} {cy}A{r} {r} 0 1 0 {cx+r} {cy}A{r} {r} 0 1 0 {cx-r} {cy}Z"

body = rr(302, 232, 420, 500, 92)
holes = [rr(382, 268, 260, 34, 17),        # destination sign
         rr(342, 330, 340, 220, 38),       # windscreen
         circle(392, 640, 32), circle(632, 640, 32),  # headlights
         rr(462, 626, 100, 28, 14)]        # grille
solid = [rr(342, 712, 76, 78, 26), rr(606, 712, 76, 78, 26),   # wheels
         rr(262, 352, 26, 92, 13), rr(736, 352, 26, 92, 13)]   # mirrors
open(f"{out}/bus.svg", "w").write(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">'
    f'<path fill="#FFFFFF" fill-rule="evenodd" d="{body}{"".join(holes)}"/>'
    f'<path fill="#FFFFFF" d="{"".join(solid)}"/></svg>')
