"""Turns the green-screen axe-chop video (H3, settler facing right) into a pixel-art strip.

Used for assets/characters/settler_chop_right.png. Usage, from any folder:
  1. Extract every frame of the video into <work>/frames:
       ffmpeg -i chop.mp4 <work>/frames/f_%03d.png
  2. python3 chop_from_video.py <work> <project folder>
It keys out the green, keeps only the frames that move (wind-up, swing, back to
rest; the long still holds are dropped - the game holds those poses itself),
shrinks everything with one shared scale so the standing pose is as tall as
settler_right.png, snaps the colours to the settler's own palette (plus a few
greys for the axe head) and gives the silhouette the settler's dark outline.
Writes settler_chop_right.png (horizontal strip) and prints the frame size and
foot offset for scripts/player.gd. Needs numpy, scipy and Pillow.
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

WORK = sys.argv[1] if len(sys.argv) > 1 else '.'
PROJ = sys.argv[2] if len(sys.argv) > 2 else '.'
# Video frames used (24 fps): rest, wind-up, swing (impact = 42), back to rest.
FRAMES = [1] + list(range(4, 17)) + list(range(38, 44)) + list(range(77, 83))


def load(i):
    return np.asarray(Image.open(f'{WORK}/frames/f_{i:03d}.png').convert('RGB')).astype(float)


def key(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    bg = (g > 120) & (g > r * 1.35) & (g > b * 1.35)
    m = ~bg
    lab, n = ndimage.label(m)
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    m = lab == 1 + int(np.argmax(sizes))
    return ndimage.binary_fill_holes(m)


def despill(a):
    a = a.copy()
    lim = np.maximum(a[..., 0], a[..., 2])
    a[..., 1] = np.minimum(a[..., 1], lim * 1.05 + 4)
    return a


def bbox(m):
    ys, xs = np.where(m)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


frames = [(despill(load(i)), key(load(i))) for i in FRAMES]
idle = np.asarray(Image.open(f'{PROJ}/assets/characters/settler_right.png').convert('RGBA'))
target_h = idle.shape[0]
b0 = bbox(frames[0][1])
k = target_h / (b0[3] - b0[1])
boxes = [bbox(m) for _, m in frames]
x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
W = round((x1 - x0) * k); H = round((y1 - y0) * k)

small = []
for a, m in frames:
    rgb = a[y0:y1, x0:x1] * m[y0:y1, x0:x1, None]
    al = m[y0:y1, x0:x1].astype(float) * 255
    pm = Image.fromarray(np.dstack([rgb, al]).clip(0, 255).astype(np.uint8), 'RGBA')
    sm = np.asarray(pm.resize((W, H), Image.BOX)).astype(float)
    alpha = sm[..., 3] / 255
    col = np.where(alpha[..., None] > 0.01, sm[..., :3] / np.maximum(alpha[..., None], 0.01), 0)
    small.append((col.clip(0, 255), alpha > 0.5))

# Palette: the settler's own colours + greys for the axe head.
pal = []
for f in ['settler_right.png', 'settler_run_right.png']:
    px = np.asarray(Image.open(f'{PROJ}/assets/characters/{f}').convert('RGBA')).reshape(-1, 4)
    pal += [tuple(p[:3]) for p in px if p[3] > 128]
pal = np.unique(np.array(pal, dtype=float), axis=0)
allpx = np.concatenate([c[m] for c, m in small])
sat = allpx.max(1) - allpx.min(1)
greys = allpx[(sat < 28) & (allpx.mean(1) > 70)]
if len(greys) > 8:
    gq = Image.fromarray(greys.reshape(1, -1, 3).astype(np.uint8), 'RGB').quantize(colors=4)
    pal = np.concatenate([pal, np.array(gq.getpalette()[:12], dtype=float).reshape(4, 3)])
dark = pal[np.argmin(pal.sum(1))]


def snap(c):
    d2 = ((c[..., None, :] - pal[None, None]) ** 2).sum(-1)
    return pal[np.argmin(d2, -1)]


strip = Image.new('RGBA', (W * len(small), H))
for i, (c, m) in enumerate(small):
    img = snap(c)
    edge = m & ~ndimage.binary_erosion(m, structure=[[0, 1, 0], [1, 1, 1], [0, 1, 0]], border_value=0)
    img[edge] = dark
    strip.paste(Image.fromarray(np.dstack([img, m * 255]).astype(np.uint8), 'RGBA'), (i * W, 0))
strip.save(f'{PROJ}/assets/characters/settler_chop_right.png')

# Foot point: middle of the feet in the rest pose, bottom of the frame.
fm = frames[0][1][b0[3] - 25:b0[3], :]
fx = np.where(fm)[1].mean()
foot = (round((fx - x0) * k), round((b0[3] - y0) * k))
print(f'frames={len(small)} size=({W}, {H}) offset=({-foot[0]}, {-foot[1] + 1}) impact_index={FRAMES.index(42)}')
