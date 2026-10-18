import math, sys
from PIL import Image, ImageDraw, ImageFilter

S = 2048            # supersampled canvas; final 1024
k = S / 1024        # scale from 1024-design units
out = sys.argv[1]

def P(x, y): return (x * k, y * k)
def layer(): return Image.new("RGBA", (S, S), (0, 0, 0, 0))

# ---------- squircle mask (macOS Big Sur grid: 824 body inside 1024) ----------
def squircle_mask(x0, y0, size, n=5.0):
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    cx, cy, a = (x0 + size / 2) * k, (y0 + size / 2) * k, size / 2 * k
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, s = math.cos(t), math.sin(t)
        pts.append((cx + a * math.copysign(abs(c) ** (2 / n), c),
                    cy + a * math.copysign(abs(s) ** (2 / n), s)))
    d.polygon(pts, fill=255)
    return m

BODY = (100, 100, 824)
mask = squircle_mask(*BODY)

# ---------- background ----------
bg = Image.new("RGBA", (S, S))
top, bot = (52, 46, 78), (16, 14, 28)
px = bg.load()
for y in range(S):
    for x in range(0, S):
        t = min(1, max(0, (0.65 * y + 0.35 * x) / S))
        px[x, y] = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,)

# purple glow bottom-right
glow = layer(); gd = ImageDraw.Draw(glow)
gd.ellipse([*P(560, 560), *P(1120, 1120)], fill=(150, 70, 200, 150))
glow = glow.filter(ImageFilter.GaussianBlur(170 * k))
bg = Image.alpha_composite(bg, glow)

# glass sheen on the top half
sheen = layer(); sd = ImageDraw.Draw(sheen)
sd.ellipse([*P(-200, -700), *P(1224, 430)], fill=(255, 255, 255, 30))
sheen = sheen.filter(ImageFilter.GaussianBlur(130 * k))
bg = Image.alpha_composite(bg, sheen)

# ---------- clock ----------
C = (512, 520); R = 292

def polar(f, r):
    a = f * 2 * math.pi - math.pi / 2
    return (C[0] + r * math.cos(a), C[1] + r * math.sin(a))

art = layer(); d = ImageDraw.Draw(art)

# face
d.ellipse([*P(C[0] - R, C[1] - R), *P(C[0] + R, C[1] + R)], fill=(255, 255, 255, 16))

# wedge: 12 → ~4:00 (orange time block)
w0, w1 = 0.0, 0.34
pts = [P(*C)] + [P(*polar(w0 + (w1 - w0) * i / 200, R)) for i in range(201)]
wl = layer(); ImageDraw.Draw(wl).polygon(pts, fill=(255, 166, 30, 150))
art = Image.alpha_composite(art, wl); d = ImageDraw.Draw(art)
for f in (w0, w1):
    d.line([P(*C), P(*polar(f, R))], fill=(255, 159, 10, 255), width=int(9 * k))

# ticks
for i in range(60):
    f = i / 60
    major = i % 5 == 0
    r0 = R - (52 if major else 30)
    d.line([P(*polar(f, r0)), P(*polar(f, R - 12))],
           fill=(255, 255, 255, 235 if major else 95),
           width=int((11 if major else 4) * k))

# ring
d.ellipse([*P(C[0] - R, C[1] - R), *P(C[0] + R, C[1] + R)],
          outline=(255, 255, 255, 245), width=int(15 * k))

# hand-drawn pen stroke (blue), slight wobble like a real marker
stroke = []
for i in range(161):
    t = i / 160
    f = 0.53 + 0.30 * t
    r = R * 0.66 + 7 * math.sin(t * 7.0)
    stroke.append(P(*polar(f, r)))
sl = layer(); s_d = ImageDraw.Draw(sl)
wpx = int(20 * k)
# stamp circles along a densely resampled path -> perfectly smooth round marker
for (ax, ay), (bx, by) in zip(stroke, stroke[1:]):
    n = max(1, int(math.hypot(bx - ax, by - ay) / 2))
    for j in range(n + 1):
        x, y = ax + (bx - ax) * j / n, ay + (by - ay) * j / n
        s_d.ellipse([x - wpx / 2, y - wpx / 2, x + wpx / 2, y + wpx / 2], fill=(64, 156, 255, 255))
for end in ():
    s_d.ellipse([end[0] - wpx / 2, end[1] - wpx / 2, end[0] + wpx / 2, end[1] + wpx / 2],
                fill=(64, 156, 255, 255))
art = Image.alpha_composite(art, sl); d = ImageDraw.Draw(art)

# center dot
d.ellipse([*P(C[0] - 14, C[1] - 14), *P(C[0] + 14, C[1] + 14)], fill=(255, 255, 255, 255))

# beads on the rim: orange = hour (at wedge start), blue = minute
def bead(f, dia, rgb):
    x, y = polar(f, R)
    rr = dia / 2
    d.ellipse([*P(x - rr - 5, y - rr - 5), *P(x + rr + 5, y + rr + 5)], fill=(20, 16, 32, 255))
    d.ellipse([*P(x - rr, y - rr), *P(x + rr, y + rr)], fill=rgb + (255,))
bead(w1, 34, (64, 156, 255))     # minute
bead(w0, 58, (255, 159, 10))     # hour

# soft shadow under clock art
sh = art.split()[3].point(lambda a: int(a * 0.45))
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0)); shadow.putalpha(sh)
shadow = shadow.filter(ImageFilter.GaussianBlur(14 * k))
off = Image.new("RGBA", (S, S), (0, 0, 0, 0)); off.paste(shadow, (0, int(10 * k)))
body = Image.alpha_composite(bg, off)
body = Image.alpha_composite(body, art)

# ---------- assemble ----------
icon = layer()
# drop shadow of the squircle
ds = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ds.putalpha(mask.point(lambda a: int(a * 0.5)))
ds = ds.filter(ImageFilter.GaussianBlur(18 * k))
icon.paste(ds, (0, int(12 * k)), ds)
body.putalpha(mask)
icon = Image.alpha_composite(icon, body)

# hairline inner border
edge = squircle_mask(BODY[0] + 1.5, BODY[1] + 1.5, BODY[2] - 3)
border = Image.new("L", (S, S), 0)
border.paste(mask)
from PIL import ImageChops
ring = ImageChops.subtract(mask, edge).point(lambda a: int(a * 0.35))
bl = Image.new("RGBA", (S, S), (255, 255, 255, 0)); bl.putalpha(ring)
icon = Image.alpha_composite(icon, bl)

icon.resize((1024, 1024), Image.LANCZOS).save(out)
print("ok", out)
