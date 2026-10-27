"""Harmonize sprite colors to the forest palette.
Ramp-aware: each source color first picks the palette ramp with the closest hue/chroma,
then the step in that ramp with the closest lightness, so shading structure survives.
Characters are not remapped (palette has no skin/hair ramps); everything gets one outline color."""
import sys, os, glob, shutil
import numpy as np
from PIL import Image

def srgb_to_lab(rgb):
    c = rgb / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ M.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 216/24389, np.cbrt(xyz), (24389/27 * xyz + 16) / 116)
    return np.stack([116*f[...,1]-16, 500*(f[...,0]-f[...,1]), 200*(f[...,1]-f[...,2])], -1)

H = lambda s: [int(s[i:i+2], 16) for i in (1, 3, 5)]
RAMPS = {
 'canopy': ['#12201f','#1c3330','#284a3d','#3a6347','#5a8152'],
 'grass':  ['#1f2e1c','#34502a','#4e6a32','#6f8c3e','#94a852'],
 'moss':   ['#2c351a','#3c4a22','#5e6a2e','#8a8a3a','#b0a64e'],
 'bark':   ['#1e1410','#3a2418','#5a3a24','#7e5532','#a87a4a'],
 'dirt':   ['#2e2218','#4a3826','#6b5236','#8f7350','#b39a72'],
 'stone':  ['#232a2e','#3b4448','#5a6468','#808a8a','#a9b0aa'],
 'autumn': ['#3e1610','#5a1f14','#8e3a1c','#c2602a','#e09a3c'],
 'red':    ['#3e1610','#7a1e26','#b8323a'],
 'purple': ['#2c3a52','#8a6ac8'],
 'glow':   ['#2c3a52','#6fd3e0'],
 'night':  ['#0b0f1a','#1a2238','#2c3a52'],
 'cream':  ['#8f7350','#c9b98a','#e8e0c8','#f2e6c4'],
}
OUTLINE = np.array(H('#1e1410'), dtype=np.uint8)
ramp_rgb = {k: np.array([H(c) for c in v], float) for k, v in RAMPS.items()}
ramp_lab = {k: srgb_to_lab(v) for k, v in ramp_rgb.items()}

def map_color(lab, allowed=None, stoney=False):
    hue = np.degrees(np.arctan2(lab[2], lab[1])) % 360; ch = np.hypot(lab[1], lab[2])
    if stoney and ch < 25 and lab[0] > 12:
        rl = ramp_lab['stone']; return ramp_rgb['stone'][np.argmin((rl[:,0]-lab[0])**2)]
    if lab[0] > 35 and (ch < 12 or ((hue < 48 or hue > 330) and ch < 30)):
        best = (0, 'stone')   # pinkish/mauve greys are stone, not dirt
        rl = ramp_lab['stone']
        i = np.argmin((rl[:,0]-lab[0])**2)
        return ramp_rgb['stone'][i]
    best = None
    for k, rl in ramp_lab.items():
        if allowed and k not in allowed: continue
        # hue/chroma match, lightness only weakly (ramps span lightness anyway)
        d = 0.15*(rl[:,0]-lab[0])**2 + (rl[:,1]-lab[1])**2 + (rl[:,2]-lab[2])**2
        s = d.min()
        if best is None or s < best[0]: best = (s, k)
    k = best[1]; rl = ramp_lab[k]
    # within the ramp: lightness first
    i = np.argmin(2.0*(rl[:,0]-lab[0])**2 + 0.3*((rl[:,1]-lab[1])**2 + (rl[:,2]-lab[2])**2))
    return ramp_rgb[k][i]

def process(path, out, remap=True, allowed=None, stoney=False):
    im = Image.open(path).convert('RGBA'); a = np.array(im)
    rgb, al = a[...,:3].astype(float), a[...,3]
    vis = al > 0
    if remap:
        cols, inv = np.unique(rgb[vis].reshape(-1,3), axis=0, return_inverse=True)
        labs = srgb_to_lab(cols)
        # tame over-saturated colors a bit before matching
        ch = np.hypot(labs[:,1], labs[:,2]); f = np.where(ch > 40, (40 + (ch-40)*0.5)/np.maximum(ch,1e-6), 1)
        labs[:,1] *= f; labs[:,2] *= f
        new = np.array([map_color(l, allowed, stoney) for l in labs])
        rgb[vis] = new[inv.ravel()]
    # unify outline: very dark pixels touching transparency
    L = srgb_to_lab(rgb)[...,0]
    t = ~vis; pad = np.pad(t, 1, constant_values=True)
    edge = pad[:-2,1:-1] | pad[2:,1:-1] | pad[1:-1,:-2] | pad[1:-1,2:]
    m = vis & edge & (L < 20)
    rgb[m] = OUTLINE
    a[...,:3] = np.clip(rgb, 0, 255).astype(np.uint8)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    Image.fromarray(a, 'RGBA').convert(Image.open(path).mode if Image.open(path).mode in ('RGB','RGBA') else 'RGBA').save(out)

src, dst = sys.argv[1], sys.argv[2]
for f in sorted(glob.glob(os.path.join(src, 'assets/**/*.png'), recursive=True)):
    rel = os.path.relpath(f, src); out = os.path.join(dst, rel)
    char = '/characters/' in f
    tiles = '/tiles/' in f
    stoney = any(w in os.path.basename(f) for w in ('node','stone','boulder','rock','pebble','campfire'))
    process(f, out, remap=not char, stoney=stoney, allowed=['grass','moss','dirt','autumn','cream','stone','bark','red'] if tiles else None)
print('done')
