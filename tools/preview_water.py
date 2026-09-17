#!/usr/bin/env python3
"""Look-dev preview for the water surface in HorizonShaders.

Same idea as tools/preview_sky.py: a numpy port of the surface maths (wave
gradients, fresnel with the reflectance floor, depth opacity, body colour,
dual-lobe sun glint, crest translucency, foam) over a fixed camera looking at
a plane of water with a varying bottom depth, so water tweaks can be judged
without launching Minecraft.

The reflected sky is the gradient plus the sun disc only - the in-game
reflection also mirrors clouds and stars through hzSkyReflection, which this
scratchpad does not port. Requires numpy.

    python3 tools/preview_water.py [out.png]
"""
import math
import struct
import sys
import zlib

import numpy as np

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/water.png"

W, H = 960, 540

WATER_ABSORPTION = 1.0
WATER_TURBIDITY = 0.50
WATER_WAVE_STRENGTH = 1.0
WATER_SHININESS = 96.0
WATER_F0 = 0.02
WAVE_COUNT = 5

WAVES = np.array([
    [1.00, 0.20, 0.35, 0.220],
    [-0.70, 0.75, 0.60, 0.140],
    [0.30, -1.00, 1.10, 0.075],
    [-0.95, -0.35, 1.80, 0.045],
    [0.60, 0.85, 2.60, 0.026],
    [-0.20, 0.50, 3.60, 0.015],
    [0.90, -0.65, 4.80, 0.009],
    [-0.55, -0.90, 6.00, 0.005],
])

TIME = 90.0
SUN = np.array([0.18, 0.32, 0.93])      # low sun ahead, across the water
SUN = SUN / np.linalg.norm(SUN)
SUN_COLOUR = np.array([1.00, 0.94, 0.84]) * 1.05
AMBIENT = np.array([0.32, 0.42, 0.60])
CAM = np.array([0.0, 66.0, 0.0])
PLANE_Y = 63.0


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


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def wave_phase_dirs():
    dirs = WAVES[:, :2].copy()
    dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
    return dirs


WDIRS = wave_phase_dirs()


def wave_gradient(x, z, view_distance):
    g = np.zeros(x.shape + (2,))
    height = np.zeros_like(x)
    for i in range(WAVE_COUNT):
        d = WDIRS[i]
        freq = WAVES[i, 2]
        amp = WAVES[i, 3]
        fade = np.exp(-freq * view_distance * 0.020)
        phase = (x * d[0] + z * d[1]) * freq + TIME * (0.55 + freq * 0.22)
        g[..., 0] += d[0] * (np.cos(phase) * amp * freq * fade)
        g[..., 1] += d[1] * (np.cos(phase) * amp * freq * fade)
        height += np.sin(phase) * amp
    ripple_fade = np.exp(-view_distance * 0.07)
    ru = x * 2.6 + TIME * 0.31
    rv = z * 2.6 - TIME * 0.19
    g[..., 0] += (noise2(ru, rv) - 0.5) * 0.30 * ripple_fade
    g[..., 1] += (noise2(ru + 37.4, rv + 37.4) - 0.5) * 0.30 * ripple_fade
    g[..., 0] += (noise2(ru * 2.7 + 11.3, rv * 2.7 + 11.3) - 0.5) * 0.14 * ripple_fade
    g[..., 1] += (noise2(ru * 2.7 + 53.1, rv * 2.7 + 53.1) - 0.5) * 0.14 * ripple_fade
    return g, height


def sky_colour(direction):
    up = direction[..., 1]
    horizon_fade = np.power(1.0 - np.clip(up, 0.0, 1.0), 3.4)
    zenith = np.array([0.105, 0.275, 0.660])
    horizon = np.array([0.430, 0.580, 0.800])
    col = zenith[None, None, :] * (1 - horizon_fade)[..., None] \
        + horizon[None, None, :] * horizon_fade[..., None]
    cosang = direction @ SUN
    disc = (cosang > 0.99980).astype(float)
    glow = np.exp((cosang - 1.0) * 2200.0)
    col = col + (disc * 12.0 + glow * 0.45)[..., None] * np.array([1.0, 0.97, 0.90])[None, None, :]
    return col


# ---------------- camera --------------------------------------------------------
u = (np.arange(W) + 0.5) / W * 2.0 - 1.0
v = 1.0 - (np.arange(H) + 0.5) / H * 2.0
uu, vv = np.meshgrid(u, v)

fov = math.radians(75.0)
pitch = math.radians(-6.0)
aspect = W / H

dx = uu * math.tan(fov / 2.0) * aspect
dy = vv * math.tan(fov / 2.0)
dz = np.ones_like(dx)

cy, sy = math.cos(pitch), math.sin(pitch)
wy = dy * cy + dz * sy
wz = -dy * sy + dz * cy
dirs = np.stack([dx, wy, wz], axis=-1)
dirs = dirs / np.linalg.norm(dirs, axis=-1, keepdims=True)

colour = np.zeros((H, W, 3))

# ---------------- sky half ------------------------------------------------------
sky_mask = dirs[..., 1] >= -0.002
colour[sky_mask] = sky_colour(dirs[sky_mask])

# ---------------- water half ----------------------------------------------------
wmask = ~sky_mask
wd = dirs[wmask]
t = (PLANE_Y - CAM[1]) / wd[..., 1]
hit = CAM[None, :] + wd * t[..., None]
x, z = hit[..., 0], hit[..., 2]
view_distance = np.linalg.norm(hit - CAM[None, :], axis=-1)

grad, height = wave_gradient(x, z, view_distance)
normal = np.stack([-grad[..., 0] * WATER_WAVE_STRENGTH,
                   np.ones_like(x),
                   -grad[..., 1] * WATER_WAVE_STRENGTH], axis=-1)
normal /= np.linalg.norm(normal, axis=-1, keepdims=True)

# bottom depth field: a shore band crossing the near water
bottom = 0.35 + 4.6 * noise2(x * 0.021 + 3.7, z * 0.021 - 1.3)
water_depth = np.clip(bottom, 0.05, 8.0)

# refracted background: sandy bottom, lit, absorbed both ways
sand = np.array([0.32, 0.27, 0.19])
absorption = np.array([0.55, 0.16, 0.12])
transmittance = np.exp(-absorption[None, :] * water_depth[..., None] * WATER_ABSORPTION * 2.0 * 1.6)
bottom_light = SUN_COLOUR * max(SUN[1], 0.0) * 0.8 + AMBIENT * 0.7
refracted = sand[None, :] * bottom_light[None, :] * transmittance

opacity = 1.0 - np.exp(-water_depth * (0.55 * WATER_ABSORPTION + WATER_TURBIDITY * 1.6))
shallow = np.array([0.055, 0.300, 0.320])
deep = np.array([0.012, 0.085, 0.130])
toward_deep = 1.0 - np.exp(-water_depth * 0.35)
density = 1.0 - np.exp(-water_depth * WATER_TURBIDITY * 2.2)
body = (shallow[None, :] * (1 - toward_deep)[..., None] + deep[None, :] * toward_deep[..., None]) \
    * (0.25 + 0.95) * (0.35 + 0.65 * density)[..., None]

ndl = np.clip(normal @ SUN, 0.0, 1.0)
surface_light = SUN_COLOUR[None, :] * ((ndl * 0.9 + 0.1)[..., None]) + AMBIENT[None, :] * 0.8

wcol = refracted * transmittance * (1.0 - opacity * 0.85)[..., None] \
    + body * surface_light * (0.45 + 0.55 * opacity)[..., None]

view_dir = wd
cos_theta = np.clip((-view_dir * normal).sum(-1), 0.0, 1.0)
xx = 1.0 - cos_theta
fresnel = WATER_F0 + (1.0 - WATER_F0) * xx * xx * xx * xx * xx
fresnel = np.maximum(fresnel, 0.14 + 0.10 * (1.0 - cos_theta))

refl_dir = view_dir - 2.0 * ((view_dir * normal).sum(-1)[..., None] * normal)
reflection = sky_colour(refl_dir)
wcol = wcol * (1 - fresnel)[..., None] + reflection * fresnel[..., None]

half_vec = SUN[None, :] - view_dir
half_vec /= np.linalg.norm(half_vec, axis=-1, keepdims=True)
ndh = np.clip((normal * half_vec).sum(-1), 0.0, 1.0)
spec = ndh ** WATER_SHININESS + (ndh ** (WATER_SHININESS * 0.22)) * 0.30
wcol += SUN_COLOUR[None, :] * (spec * 2.2 * np.clip(ndl, 0, 1))[..., None]

crest = sstep(0.08, 0.26, height)
crest_back = np.clip(view_dir @ SUN, 0.0, 1.0) ** 2
wcol += (crest * crest_back)[..., None] * np.array([0.10, 0.45, 0.42])[None, :] * 0.55

shore = 1.0 - sstep(0.05, 0.42, water_depth)
crest_f = sstep(0.14, 0.34, height)
foam = np.clip(shore * 0.75 + crest_f * shore * 1.4 + crest_f * 0.06, 0, 1)
wcol = wcol * (1 - foam * 0.85)[..., None] + (np.array([0.85, 0.90, 0.92]) * surface_light) * (foam * 0.85)[..., None]

colour[wmask] = wcol

# ---------------- tonemap, gamma, png --------------------------------------------
colour = colour * 1.9
colour = colour / (1.0 + colour)
colour = np.clip(colour, 0, 1) ** (1 / 2.2)
pixels = (colour * 255).astype(np.uint8)

raw = b"".join(b"\x00" + pixels[y].tobytes() for y in range(H))


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw, 6))
png += chunk(b"IEND", b"")
open(OUT, "wb").write(png)
print("wrote", OUT)
