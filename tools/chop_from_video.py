"""Turns the green-screen axe-chop video (H3, settler facing right) into a pixel-art strip.

Used for assets/characters/settler_chop_right.png (ClipProj_H3_00013),
settler_chop_left.png (ClipProj_H3_00005) and the pickaxe swing
settler_mine_right.png (ClipProj_H3_00021, side "mine_right") and
settler_mine_left.png (ClipProj_H3_00023, side "mine_left"), and the spade dig
settler_dig_right.png (ClipProj_H3_00025, side "dig_right"), and watering
settler_water_right.png (ClipProj_H3_00029, side "water_right"), and sneaking
settler_sneak_right.png (ClipProj_H3_00031, side "sneak_right").
Usage, from any folder:
  1. Extract every frame of the video into <work>/frames:
       ffmpeg -i chop.mp4 <work>/frames/f_%03d.png
  2. python3 chop_from_video.py <work> <project folder> [right|left]
It keys out the green, keeps only the frames that move (wind-up, swing, back to
rest; the long still holds are dropped - the game holds those poses itself),
shrinks everything with one shared scale so the standing pose is as tall as
settler_right.png, snaps the colours to the settler's own palette (plus a few
greys for the axe head) and gives the silhouette the settler's dark outline.
Writes settler_chop_right.png (horizontal strip) and prints the frame size and
foot offset for scripts/player.gd. Needs numpy, scipy and Pillow.

NOTE: the game's art has since been recoloured to the forest palette with
tools/recolor.py. Re-running this script writes un-recoloured images, so run
recolor.py on them afterwards (python3 tools/recolor.py <src dir> <out dir>).
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

WORK = sys.argv[1] if len(sys.argv) > 1 else '.'
PROJ = sys.argv[2] if len(sys.argv) > 2 else '.'
SIDE = sys.argv[3] if len(sys.argv) > 3 else 'right'
# Video frames used (24 fps): rest, wind-up, swing, then back to rest.
# The long still holds are left out; the game holds those poses itself.
# 'ref' = the standing frame used for the size and the foot point (default: the
# first frame); 'out' = output file name in assets/characters/.
VIDEOS = {
    # ClipProj_H3_00018 (facing right): ~12 fps (most frames show twice), so only
    # the distinct ones; wind-up to 12, swing 20-21, impact = video frame 23.
    'right': {'frames': [1, 6, 7, 9, 10, 11, 12, 20, 21, 23, 33, 35, 37], 'impact': 23},
    # ClipProj_H3_00016 (running right): one clean loop = video frames 5-17
    # (frame 18 matches 5). Sized and anchored on the standing frame 1.
    # Not in use: the game keeps the original run strip (writing this
    # overwrites assets/characters/settler_run_right.png).
    'run_right': {'frames': list(range(5, 18)), 'ref': 1, 'out': 'settler_run_right.png'},
    # ClipProj_H3_00005 (facing left): impact = video frame 23, held at 24.
    'left': {'frames': [1] + list(range(3, 16)) + list(range(19, 25)) + list(range(31, 37)), 'impact': 23},
    # ClipProj_H3_00021 (pickaxe, facing right): rest, raise overhead (held 12-19),
    # strike down to the right (impact = video frame 23, crouched), hold, back up.
    # Only the distinct frames; the game holds the poses (durations in player.gd MINE).
    # Used for both sides for now (the left side is this strip mirrored).
    'mine_right': {'frames': [1, 7, 8, 10, 12, 19, 20, 22, 23, 33, 35, 37], 'impact': 23,
                   'out': 'settler_mine_right.png'},
    # ClipProj_H3_00023 (pickaxe, facing left): rest, raise overhead (held 12-18),
    # strike down to the left (impact = video frame 23), hold, back up.
    'mine_left': {'frames': [1, 4, 6, 8, 10, 12, 14, 19, 21, 23, 33, 35, 37, 38], 'impact': 23,
                  'out': 'settler_mine_left.png'},
    # ClipProj_H3_00025 (spade, facing right): push the blade into the ground,
    # lever (the dig = video frame 19), lift the dirt, back to rest. Also used
    # mirrored for facing left.
    'dig_right': {'frames': [1, 3, 4, 6, 10, 12, 15, 16, 18, 19, 21, 23, 25, 27, 31, 33, 35, 37],
                  'impact': 19, 'out': 'settler_dig_right.png'},
    # ClipProj_H3_00029 (watering can, facing right): lift the can, tilt, pour
    # (frames 19-28; the stream itself is drawn by the game as particles, the
    # video's faint water is keyed out), lower it. Mirrored for facing left.
    'water_right': {'frames': [1, 7, 9, 11, 17, 19, 21, 23, 25, 27, 29, 31, 33, 35],
                    'impact': 19, 'out': 'settler_water_right.png'},
    # ClipProj_H3_00031 (sneaking, facing right): strip frame 0 = crouched still
    # (video 11), frames 1-4 = the crouched step loop (19, 23, 25, 27; 31 matches
    # 19). Sized on the standing frame 1. Mirrored for facing left.
    'sneak_right': {'frames': [11, 19, 23, 25, 27], 'ref': 1, 'out': 'settler_sneak_right.png'},
}
FRAMES = VIDEOS[SIDE]['frames']
REF = VIDEOS[SIDE].get('ref', FRAMES[0])
OUT = VIDEOS[SIDE].get('out', f'settler_chop_{SIDE}.png')


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
ref_mask = key(load(REF))
b0 = bbox(ref_mask)
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
strip.save(f'{PROJ}/assets/characters/{OUT}')

# Foot point: middle of the feet in the rest pose, bottom of the frame.
fm = ref_mask[b0[3] - 25:b0[3], :]
fx = np.where(fm)[1].mean()
foot = (round((fx - x0) * k), round((b0[3] - y0) * k))
print(f'frames={len(small)} size=({W}, {H}) offset=({-foot[0]}, {-foot[1] + 1}) impact_index={FRAMES.index(VIDEOS[SIDE]["impact"]) if "impact" in VIDEOS[SIDE] else "-"}')
