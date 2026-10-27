"""Turns green-screen animal videos (H3 etc.) into small pixel-art sprite strips.

Used for the rabbit (assets/characters/rabbit/). Usage, from any folder:
  1. Extract every frame of each video into <work>/fr_side, <work>/fr_up, <work>/fr_down
     (side = facing right, up = away from the camera, down = towards it):
       ffmpeg -i side.mp4 <work>/fr_side/%03d.png      (same for up / down)
  2. python3 rabbit_from_video.py <sitting height px> <out folder> <work>
It keys out the green, finds the cleanest looping hop in each video (frame 1 =
the idle pose), shrinks everything with one shared scale so the front-facing
sitting pose is <sitting height> px tall, snaps all frames to one shared
palette and gives the silhouette a crisp dark outline. Writes
<animal>_<dir>.png (idle), <animal>_run_<dir>.png (strips) and meta.json
(frame counts, frame size, foot point). Needs numpy, scipy and Pillow.
"""
import numpy as np, sys, json
from PIL import Image
from scipy import ndimage
S = sys.argv[3] if len(sys.argv) > 3 else '.'
TARGET_H = float(sys.argv[1]) if len(sys.argv) > 1 else 15.0   # sitting front-view height in px
import os as _os
N = len([f for f in _os.listdir(f'{S}/fr_side') if f.endswith('.png')])
def load(d, i):
    return np.asarray(Image.open(f'{S}/fr_{d}/{i:03d}.png').convert('RGB')).astype(float)
def key(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    bg = (g > 120) & (g > r * 1.35) & (g > b * 1.35)
    m = ~bg
    lab, n = ndimage.label(m)
    if n == 0:
        return m
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    keep = 1 + int(np.argmax(sizes))
    m = lab == keep
    m = ndimage.binary_fill_holes(m)
    return m
def despill(a):
    a = a.copy()
    lim = np.maximum(a[..., 0], a[..., 2])
    a[..., 1] = np.minimum(a[..., 1], lim * 1.05 + 4)
    return a

frames = {}
for d in ['side', 'up', 'down']:
    fs = []
    for i in range(1, N + 1):
        a = load(d, i)
        fs.append((despill(a), key(a)))
    frames[d] = fs

def sig(m):
    return np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize((48, 48), Image.BILINEAR)).astype(float) / 255
result = {}
for d, fs in frames.items():
    sigs = [sig(m) for _, m in fs]
    best = None
    for L in range(6, 31):
        for s in range(14, N - L - 1):
            e = np.abs(sigs[s] - sigs[s + L]).mean()
            # also the loop must actually move (not a still section)
            motion = np.mean([np.abs(sigs[s + k] - sigs[s + k + 1]).mean() for k in range(L)])
            score = e - 0.15 * motion
            if best is None or score < best[0]:
                best = (score, L, s, e, motion)
    _, L, s, e, motion = best
    result[d] = {'L': L, 's': s, 'seam': round(e, 4), 'motion': round(motion, 4)}
print(json.dumps(result))
json.dump(result, open(f'{S}/loops.json', 'w'))

# ---- build strips ----
OUT = sys.argv[2] if len(sys.argv) > 2 else S + '/out'
import os
os.makedirs(OUT, exist_ok=True)
def bbox(m):
    ys, xs = np.where(m)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
idle_h = {d: bbox(frames[d][0][1])[3] - bbox(frames[d][0][1])[1] for d in frames}
k = TARGET_H / idle_h['down']                       # same scale for every direction
meta = {}
small = {}
for d, fs in frames.items():
    L, s = result[d]['L'], result[d]['s']
    sel = [fs[0]] + [fs[s + i] for i in range(L)]   # idle first, then the hop loop
    boxes = [bbox(m) for _, m in sel]
    x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
    W = max(1, round((x1 - x0) * k)); H = max(1, round((y1 - y0) * k))
    outs = []
    for a, m in sel:
        rgb = a[y0:y1, x0:x1] * m[y0:y1, x0:x1, None]
        al = m[y0:y1, x0:x1].astype(float)
        rgba = np.dstack([rgb, al * 255]).astype(np.uint8)
        im = Image.fromarray(rgba, 'RGBA')
        # premultiplied box downsample
        pm = Image.fromarray(np.dstack([rgb, al * 255]).clip(0, 255).astype(np.uint8), 'RGBA')
        sm = np.asarray(pm.resize((W, H), Image.BOX)).astype(float)
        alpha = sm[..., 3] / 255
        col = np.where(alpha[..., None] > 0.01, sm[..., :3] / np.maximum(alpha[..., None], 0.01), 0)
        outs.append((col.clip(0, 255), alpha > 0.5))
    small[d] = outs
    ib = bbox(sel[0][1])
    meta[d] = {'frames': L, 'size': [W, H],
               'foot': [round(((ib[0] + ib[2]) / 2 - x0) * k), round((ib[3] - y0) * k)]}
# shared palette from all opaque pixels
allpx = np.concatenate([c[m] for d in small for c, m in small[d]])
pal_img = Image.fromarray(allpx.reshape(1, -1, 3).astype(np.uint8), 'RGB').quantize(colors=18, method=Image.Quantize.MAXCOVERAGE)
pal = np.array(pal_img.getpalette()[:54]).reshape(18, 3)
dark = pal[np.argmin(pal.sum(1))]
def snap(c):
    d2 = ((c[..., None, :] - pal[None, None]) ** 2).sum(-1)
    return pal[np.argmin(d2, -1)]
for d in small:
    W, H = meta[d]['size']
    tiles = []
    for c, m in small[d]:
        img = snap(c)
        # crisp silhouette: opaque pixels touching transparency get the outline colour
        edge = m & ~ndimage.binary_erosion(m, structure=[[0, 1, 0], [1, 1, 1], [0, 1, 0]], border_value=0)
        img[edge] = dark
        rgba = np.dstack([img, m * 255]).astype(np.uint8)
        tiles.append(Image.fromarray(rgba, 'RGBA'))
    name = {'side': 'right', 'up': 'up', 'down': 'down'}[d]
    tiles[0].save(f'{OUT}/rabbit_{name}.png')
    strip = Image.new('RGBA', (W * (len(tiles) - 1), H))
    for i, t in enumerate(tiles[1:]):
        strip.paste(t, (i * W, 0))
    strip.save(f'{OUT}/rabbit_run_{name}.png')
    meta[d]['file'] = name
print(json.dumps(meta))
json.dump(meta, open(f'{OUT}/meta.json', 'w'))
