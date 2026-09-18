#!/usr/bin/env python3
"""Look-dev preview for the cloud deck in HorizonShaders/shaders/lib/sky.glsl.

This is a scratchpad, not a source of truth: it ports the cloud maths of
hzCloudField / hzCloudCoverage / hzCloudLayer (hash, value noise, fBm, slab
intersection, per-metre extinction, beer-lambert + powder + rim lighting,
cirrus) to numpy so a cloud change can be *looked at* in seconds instead of
launching Minecraft. It renders a fixed camera into a PNG.

It deliberately does not import anything from the pack; when the shader
changes, the constants and formulas below have to be copied across by hand.
Requires numpy (pip install --user numpy).

    python3 tools/preview_sky.py [density] [layers] [octaves] [out.png]

Defaults match the Medium profile: 0.62 density, 4 layers, 5 octaves.
"""
import math
import struct
import sys
import zlib

import numpy as np

HZ_CLOUD_SCALE = 0.0045
HZ_CLOUD_THICKNESS = 46.0
HZ_CLOUD_EXTINCTION = 0.16          # per unit density per metre
HZ_CIRRUS_ALTITUDE = 2.7
HZ_CLOUD_MAX_DIST = 8000.0

CLOUD_DENSITY = float(sys.argv[1]) if len(sys.argv) > 1 else 0.62
CLOUD_LAYERS = int(sys.argv[2]) if len(sys.argv) > 2 else 4
CLOUD_OCTAVES = int(sys.argv[3]) if len(sys.argv) > 3 else 5
OUT = sys.argv[4] if len(sys.argv) > 4 else "/tmp/sky.png"
PITCH = float(sys.argv[5]) if len(sys.argv) > 5 else 28.0

W, H = 960, 540
WIND = np.array([4.5, 0.79])        # frameTimeCounter * (4.0, 0.7) * speed * scale
SUN = np.array([0.25, 0.86, 0.20])
SUN = SUN / np.linalg.norm(SUN)
CAM_Y = 70.0
ALT = 192.0


def fract(x):
    return x - np.floor(x)


def hash21(px, py):
    return fract(np.sin(px * 127.1 + py * 311.7) * 43758.5453123)


def noise2(px, py):
    gx = np.floor(px)
    gy = np.floor(py)
    lx = px - gx
    ly = py - gy
    fx = lx * lx * (3.0 - 2.0 * lx)
    fy = ly * ly * (3.0 - 2.0 * ly)
    a = hash21(gx, gy)
    b = hash21(gx + 1.0, gy)
    c = hash21(gx, gy + 1.0)
    d = hash21(gx + 1.0, gy + 1.0)
    ab = a + (b - a) * fx
    cd = c + (d - c) * fx
    return ab + (cd - ab) * fy


def fbm2(px, py, octaves):
    total = np.zeros_like(px)
    amp = 0.5
    freq = 1.0
    norm = 0.0
    for _ in range(octaves):
        total += amp * noise2(px * freq, py * freq)
        norm += amp
        amp *= 0.5
        freq *= 2.0
    return total / norm


def sstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def field(px, py):
    ux = px * HZ_CLOUD_SCALE + WIND[0]
    uy = py * HZ_CLOUD_SCALE + WIND[1]
    wx = noise2(ux * 0.31 + 7.31, uy * 0.31 + 7.31) - 0.5
    wy = noise2(ux * 0.31 - 4.17, uy * 0.31 - 4.17) - 0.5
    return fbm2(ux + wx * 0.35, uy + wy * 0.35, CLOUD_OCTAVES)


def coverage(f):
    threshold = 0.68 + (0.42 - 0.68) * CLOUD_DENSITY
    return sstep(threshold, threshold + 0.15, f)


# ---------------- camera rays -------------------------------------------------
u = (np.arange(W) + 0.5) / W * 2.0 - 1.0
v = 1.0 - (np.arange(H) + 0.5) / H * 2.0
uu, vv = np.meshgrid(u, v)

fov = math.radians(75.0)
pitch = math.radians(PITCH)
aspect = W / H

dx = uu * math.tan(fov / 2.0) * aspect
dy = vv * math.tan(fov / 2.0)
dz = np.ones_like(dx)

cy, sy = math.cos(pitch), math.sin(pitch)
wy = dy * cy + dz * sy
wz = -dy * sy + dz * cy
dirs = np.stack([dx, wy, wz], axis=-1)
dirs = dirs / np.linalg.norm(dirs, axis=-1, keepdims=True)

# ---------------- sky gradient -------------------------------------------------
up = dirs[..., 1]
horizon_fade = np.power(1.0 - np.clip(up, 0.0, 1.0), 3.4)
zenith = np.array([0.105, 0.275, 0.660])
horizon = np.array([0.430, 0.580, 0.800])
colour = zenith[None, None, :] * (1 - horizon_fade)[..., None] \
    + horizon[None, None, :] * horizon_fade[..., None]

# ---------------- cloud deck ---------------------------------------------------
transmittance = np.ones((H, W))
scatter = np.zeros((H, W, 3))

dy_ = dirs[..., 1]
valid = np.abs(dy_) >= 0.004

t_base = (ALT - CAM_Y) / np.where(valid, dy_, 1.0)
t_top = (ALT + HZ_CLOUD_THICKNESS - CAM_Y) / np.where(valid, dy_, 1.0)
enter = np.maximum(np.minimum(t_base, t_top), 0.0)
exit_ = np.minimum(np.maximum(t_base, t_top), HZ_CLOUD_MAX_DIST)
valid = valid & (exit_ > enter)

sun_up = max(SUN[1], 0.16)
light_colour = np.array([1.00, 0.94, 0.84]) * 0.95
step_length = np.maximum(exit_ - enter, 0.0) / CLOUD_LAYERS

for i in range(CLOUD_LAYERS):
    height = (i + 0.5) / CLOUD_LAYERS
    t = enter + (exit_ - enter) * height
    px = dirs[..., 0] * t
    pz = dirs[..., 2] * t

    profile = sstep(0.0, 0.18, height) * (1.0 - sstep(0.55, 1.0, height))

    f = field(px, pz)
    detail = fbm2(px * (HZ_CLOUD_SCALE * 5.0) + WIND[0] * 1.6,
                  pz * (HZ_CLOUD_SCALE * 5.0) + WIND[1] * 1.6, 3)
    dw = (0.10 + 0.55 * height * height) * (1.0 - sstep(2500.0, 7000.0, t))
    fine = fbm2(px * (HZ_CLOUD_SCALE * 13.0) + WIND[0] * 2.3,
                pz * (HZ_CLOUD_SCALE * 13.0) + WIND[1] * 2.3, 2)
    fw = 0.12 * height * height * (1.0 - sstep(1500.0, 4500.0, t))
    cov = coverage(f - (1.0 - detail) * dw - (1.0 - fine) * fw)
    density = cov * profile

    sun_px = px + SUN[0] * (HZ_CLOUD_THICKNESS * (1.0 - height) / sun_up)
    sun_pz = pz + SUN[2] * (HZ_CLOUD_THICKNESS * (1.0 - height) / sun_up)
    optical = coverage(field(sun_px, sun_pz)) * (1.0 - height * 0.35)
    beer = np.exp(-optical * 3.0)
    powder = 1.0 - np.exp(-density * 2.4)
    fwd = np.clip((dirs @ SUN) * 0.5 + 0.5, 0, 1) ** 6

    rim = sstep(0.0, 0.22, cov) * (1.0 - sstep(0.22, 0.60, cov))

    amb = np.array([0.16, 0.20, 0.28]) * (1 - height) + np.array([0.40, 0.50, 0.66]) * height
    luminance = light_colour[None, None, :] * (beer * (0.50 + 0.90 * powder) + fwd * beer * 1.10)[..., None] \
        + light_colour[None, None, :] * (rim * (0.30 + 0.50 * fwd))[..., None] \
        + amb[None, None, :]
    luminance = luminance * (0.82 + 0.36 * detail)[..., None]

    extinction = density * HZ_CLOUD_EXTINCTION * step_length
    absorbed = 1.0 - np.exp(-extinction)
    alive = valid & (transmittance >= 0.03) & (density > 0.002)

    scatter = scatter + alive[..., None] * (transmittance * absorbed)[..., None] * luminance
    transmittance = np.where(alive, transmittance * np.exp(-extinction), transmittance)

# ---------------- cirrus ---------------------------------------------------------
t = (ALT * HZ_CIRRUS_ALTITUDE - CAM_Y) / np.where(dy_ > 0.02, dy_, 1.0)
ok = (dy_ > 0.02) & (t > 0) & (t < HZ_CLOUD_MAX_DIST) & (transmittance > 0.05)
cpx = dirs[..., 0] * t
cpz = dirs[..., 2] * t
cux = cpx * (HZ_CLOUD_SCALE * 2.1) + WIND[0] * 0.30
cuy = cpz * (HZ_CLOUD_SCALE * 2.1) + WIND[1] * 0.30
wisps = fbm2(cux * 1.0, cuy * 2.7, 3)
cirrus = sstep(0.60, 0.86, wisps) * 0.40
lum_c = light_colour * 0.85 + np.array([0.50, 0.60, 0.78])
absorbed = cirrus * 0.55
scatter = scatter + (ok * absorbed)[..., None] * lum_c[None, None, :]
transmittance = np.where(ok, transmittance * (1.0 - absorbed), transmittance)

# ---------------- fades ----------------------------------------------------------
df = np.clip((exit_ - HZ_CLOUD_MAX_DIST * 0.30) / (HZ_CLOUD_MAX_DIST * 0.62), 0, 1)
distance_fade = 1.0 - df * df * (3 - 2 * df)
hf = np.clip((np.abs(dy_) - 0.012) / 0.038, 0, 1)
horizon_fade_c = hf * hf * (3 - 2 * hf)
fade = np.where(valid, distance_fade * horizon_fade_c, 0.0)

colour = colour * np.where(valid, (1.0 - (1.0 - transmittance) * fade), 1.0)[..., None] \
    + scatter * fade[..., None]

# ---------------- sun disc, tonemap, gamma ---------------------------------------
cosang = dirs @ SUN
disc = (cosang > 0.99980).astype(float)
glow = np.exp((cosang - 1.0) * 2200.0)
colour = colour + (disc * 12.0 + glow * 0.45)[..., None] * np.array([1.0, 0.97, 0.90])[None, None, :]

colour = colour * 1.0                      # EXPOSURE
colour = (colour * (1.0 + colour / 16.0)) / (1.0 + colour)   # Reinhard extended, white=4
colour = np.clip(colour, 0, 1) ** (1 / 2.2)

pixels = (colour * 255).astype(np.uint8)

# ---------------- write png ------------------------------------------------------
raw = b"".join(b"\x00" + pixels[y].tobytes() for y in range(H))


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw, 6))
png += chunk(b"IEND", b"")
open(OUT, "wb").write(png)
print("wrote", OUT, "density", CLOUD_DENSITY, "layers", CLOUD_LAYERS, "octaves", CLOUD_OCTAVES)
