#!/usr/bin/env python3
# Writes lib/screens/polymarket/components/us_map_geometry.dart: the US
# state outlines the Predictions state map draws (us_state_map.dart).
#
# Source: US Census Bureau, 2023 cartographic boundary file
# cb_2023_us_state_20m (1:20,000,000), public domain as a work of the US
# federal government:
#   https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_state_20m.zip
#
# Usage (standard library only):
#   unzip cb_2023_us_state_20m.zip -d census
#   python3 tool/us_map_geometry.py census/cb_2023_us_state_20m.shp \
#       census/cb_2023_us_state_20m.dbf \
#       lib/screens/polymarket/components/us_map_geometry.dart
#
# Projection: Albers equal-area conic for the lower 48 (parallels 29.5 and
# 45.5 N), Alaska at 0.35 scale and Hawaii as insets bottom left (the
# layout of d3.geoAlbersUsa); Douglas-Peucker simplified, integer
# coordinates. Puerto Rico and the island areas are left out.
import math, struct, sys

shp_path, dbf_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

def read_dbf(path):
    with open(path, 'rb') as f:
        data = f.read()
    nrec = struct.unpack('<I', data[4:8])[0]
    hlen, rlen = struct.unpack('<HH', data[8:12])
    fields = []
    off = 32
    while data[off] != 0x0D:
        name = data[off:off+11].split(b'\x00')[0].decode()
        ftype = chr(data[off+11]); flen = data[off+16]
        fields.append((name, ftype, flen)); off += 32
    recs = []
    for i in range(nrec):
        base = hlen + i*rlen + 1
        rec = {}
        p = base
        for name, ftype, flen in fields:
            rec[name] = data[p:p+flen].decode('utf-8', 'replace').strip(); p += flen
        recs.append(rec)
    return recs

def read_shp(path):
    with open(path, 'rb') as f:
        data = f.read()
    off = 100
    shapes = []
    while off < len(data):
        recno, clen = struct.unpack('>II', data[off:off+8]); off += 8
        content = data[off:off+clen*2]; off += clen*2
        stype = struct.unpack('<i', content[0:4])[0]
        if stype == 0:
            shapes.append([]); continue
        assert stype == 5, stype
        nparts, npts = struct.unpack('<ii', content[36:44])
        parts = list(struct.unpack('<%di' % nparts, content[44:44+4*nparts]))
        po = 44 + 4*nparts
        pts = [struct.unpack('<dd', content[po+16*k:po+16*k+16]) for k in range(npts)]
        rings = []
        for j in range(nparts):
            a = parts[j]; b = parts[j+1] if j+1 < nparts else npts
            rings.append(pts[a:b])
        shapes.append(rings)
    return shapes

def albers(lat1, lat2, lat0, lon0):
    r = math.radians
    n = (math.sin(r(lat1)) + math.sin(r(lat2))) / 2
    C = math.cos(r(lat1))**2 + 2*n*math.sin(r(lat1))
    rho0 = math.sqrt(C - 2*n*math.sin(r(lat0))) / n
    def proj(lon, lat):
        if lon > 0: lon -= 360  # Aleutians past the antimeridian
        rho = math.sqrt(C - 2*n*math.sin(r(lat))) / n
        th = n * r(lon - lon0)
        return (rho*math.sin(th), -(rho0 - rho*math.cos(th)))  # y down
    return proj

def area(ring):
    s = 0
    for i in range(len(ring)):
        x1, y1 = ring[i]; x2, y2 = ring[(i+1) % len(ring)]
        s += x1*y2 - x2*y1
    return s/2

def dp(pts, tol):
    if len(pts) < 3: return pts
    keep = [False]*len(pts); keep[0] = keep[-1] = True
    stack = [(0, len(pts)-1)]
    while stack:
        a, b = stack.pop()
        ax, ay = pts[a]; bx, by = pts[b]
        dx, dy = bx-ax, by-ay; L = math.hypot(dx, dy)
        best, bi = -1, -1
        for i in range(a+1, b):
            px, py = pts[i]
            d = abs(dy*px - dx*py + bx*ay - by*ax)/L if L else math.hypot(px-ax, py-ay)
            if d > best: best, bi = d, i
        if best > tol:
            keep[bi] = True; stack += [(a, bi), (bi, b)]
    return [p for p, k in zip(pts, keep) if k]

def simplify_ring(ring, tol):
    # Split the closed ring at its farthest point so DP has two ends.
    r = ring[:-1] if ring[0] == ring[-1] else ring[:]
    if len(r) < 4: return r
    far = max(range(len(r)), key=lambda i: (r[i][0]-r[0][0])**2 + (r[i][1]-r[0][1])**2)
    a = dp(r[:far+1], tol); b = dp(r[far:] + [r[0]], tol)
    return a[:-1] + b[:-1]

recs = read_dbf(dbf_path)
shapes = read_shp(shp_path)
L48 = albers(29.5, 45.5, 37.5, -96)
AK = albers(55, 65, 50, -154)
HI = albers(8, 18, 3, -157)

states = {}
for rec, rings in zip(recs, shapes):
    code = rec['STUSPS']
    if rec['STATEFP'] in ('72', '60', '66', '69', '78'): continue
    states[code] = (rec['NAME'], rings)

def project(code, rings):
    p = AK if code == 'AK' else HI if code == 'HI' else L48
    return [[p(lon, lat) for lon, lat in ring] for ring in rings]

proj = {c: (n, project(c, r)) for c, (n, r) in states.items()}

def bounds(ringsets):
    xs = [x for rs in ringsets for r in rs for x, _ in r]
    ys = [y for rs in ringsets for r in rs for _, y in r]
    return min(xs), min(ys), max(xs), max(ys)

W = 960.0
pad = 8.0
l48 = [r for c, (n, r) in proj.items() if c not in ('AK', 'HI')]
x0, y0, x1, y1 = bounds(l48)
s = (W - 2*pad) / (x1 - x0)
H48 = (y1 - y0) * s
def t48(x, y): return (pad + (x - x0)*s, pad + (y - y0)*s)

# Alaska at 0.35 of the lower-48 scale, bottom left; Hawaii at full
# scale, to its right (d3.geoAlbersUsa's layout).
ax0, ay0, ax1, ay1 = bounds([proj['AK'][1]])
sak = s * 0.35
ak_h = (ay1 - ay0) * sak
H = H48 + 2*pad
ak_left, ak_bottom = pad, H48 + pad + 10
def tak(x, y): return (ak_left + (x - ax0)*sak, ak_bottom - ak_h + (y - ay0)*sak)
hx0, hy0, hx1, hy1 = bounds([proj['HI'][1]])
shi = s * 1.0
hi_h = (hy1 - hy0) * shi
ak_w = (ax1 - ax0) * sak
hi_left = ak_left + ak_w + 24
def thi(x, y): return (hi_left + (x - hx0)*shi, ak_bottom - hi_h + (y - hy0)*shi)

H = math.ceil(max(H48 + 2*pad, ak_bottom + pad))
TOL = float(sys.argv[4]) if len(sys.argv) > 4 else 0.9
MIN_AREA = float(sys.argv[5]) if len(sys.argv) > 5 else 6.0

def point_in(ring, x, y):
    inside = False
    n = len(ring)
    for i in range(n):
        x1_, y1_ = ring[i]; x2_, y2_ = ring[(i+1) % n]
        if (y1_ > y) != (y2_ > y):
            xi = x1_ + (y - y1_)*(x2_ - x1_)/(y2_ - y1_)
            if x < xi: inside = not inside
    return inside

def seg_dist(px, py, ax_, ay_, bx_, by_):
    dx, dy = bx_-ax_, by_-ay_
    L2 = dx*dx + dy*dy
    t = 0 if L2 == 0 else max(0, min(1, ((px-ax_)*dx + (py-ay_)*dy)/L2))
    return math.hypot(px-(ax_+t*dx), py-(ay_+t*dy))

def label_point(ring):
    xs = [p[0] for p in ring]; ys = [p[1] for p in ring]
    bx0, by0, bx1, by1 = min(xs), min(ys), max(xs), max(ys)
    best, bp = -1, ((bx0+bx1)/2, (by0+by1)/2)
    N = 40
    for i in range(N+1):
        for j in range(N+1):
            x = bx0 + (bx1-bx0)*i/N; y = by0 + (by1-by0)*j/N
            if not point_in(ring, x, y): continue
            d = min(seg_dist(x, y, *ring[k], *ring[(k+1) % len(ring)]) for k in range(len(ring)))
            if d > best: best, bp = d, (x, y)
    return bp, best

out = {}
labels = {}
total_pts = 0
for code in sorted(proj):
    name, rings = proj[code]
    t = tak if code == 'AK' else thi if code == 'HI' else t48
    rs = [[t(x, y) for x, y in ring] for ring in rings]
    rs.sort(key=lambda r: -abs(area(r)))
    kept = []
    for i, r in enumerate(rs):
        a = abs(area(r))
        if i > 0 and a < MIN_AREA: continue
        sr = simplify_ring(r, TOL if a > 200 else TOL*0.5)
        sr = [(round(x), round(y)) for x, y in sr]
        dedup = []
        for p in sr:
            if not dedup or dedup[-1] != p: dedup.append(p)
        if len(dedup) > 1 and dedup[0] == dedup[-1]: dedup.pop()
        if len(dedup) < 3: 
            if i == 0: dedup = [(round(x), round(y)) for x, y in r[:-1]]
            else: continue
        kept.append(dedup)
    total_pts += sum(len(k) for k in kept)
    d = ''.join('M' + ' '.join('%d %d' % p for p in k[:1]) + 'L' + ' '.join('%d %d' % p for p in k[1:]) + 'Z' for k in kept)
    out[code] = (name, d)
    (lx, ly), rad = label_point(kept[0])
    labels[code] = (round(lx, 1), round(ly, 1), round(rad, 1))

with open(out_path, 'w') as f:
    f.write('// GENERATED by tool/us_map_geometry.py from the US Census Bureau 2023\n')
    f.write('// cartographic boundary file cb_2023_us_state_20m (public domain, a work\n')
    f.write('// of the US federal government): Albers equal-area (29.5/45.5 N), Alaska\n')
    f.write('// at 0.35 scale and Hawaii as insets, Douglas-Peucker simplified to %.1f\n' % TOL)
    f.write('// units, integer coordinates in a %d x %d box. Do not edit by hand.\n\n' % (W, H))
    f.write("import 'dart:ui' show Offset;\n\n")
    f.write('/// Width of the box the outlines are drawn in.\nconst double kUsMapWidth = %d;\n\n' % W)
    f.write('/// Height of the box the outlines are drawn in.\nconst double kUsMapHeight = %d;\n\n' % H)
    f.write('/// Each state\'s (and DC\'s) outline by USPS code, as SVG path data of\n/// absolute M / L / Z commands only.\nconst Map<String, String> kUsStatePaths = {\n')
    for code in sorted(out):
        f.write("  '%s':\n      '%s',\n" % (code, out[code][1]))
    f.write('};\n\n')
    f.write('/// Where a state\'s code label sits (the point of its largest part\n/// farthest from its edge) and how far that point is from the edge.\nconst Map<String, ({Offset at, double room})> kUsStateLabelPoints = {\n')
    for code in sorted(labels):
        lx, ly, rad = labels[code]
        f.write("  '%s': (at: Offset(%s, %s), room: %s),\n" % (code, lx, ly, rad))
    f.write('};\n')
print('states', len(out), 'points', total_pts, 'H', H, file=sys.stderr)
