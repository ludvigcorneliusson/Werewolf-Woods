"""Item / tool icons from the user's big pixel-art images (tools/art/src_*.png).

Each source is pixel art blown up ~12-35x. This script:
  1. finds the source's pixel grid (cell size + offset) and samples one colour
     per cell -> the native art (alpha from the source),
  2. tools only: rotates it 45 degrees the RotSprite way (Scale2x three times =
     8x, rotate with nearest-neighbour, then back down) so the head points to the
     top right like the old axe icon,
  3. shrinks it to fit the 52 px HUD slot (icon area ~40 px), picking the most
     common colour in each block so the palette stays the art's own,
  4. writes assets/ui/<name>.png (1 icon px = 1 screen px in the slot).
Map props in PROP_ART (the copper ore node) only get step 1 -> assets/props/.

Usage: python3 tools/make_item_icons.py <project dir>

NOTE: the game's art has since been recoloured to the forest palette with
tools/recolor.py. Re-running this script writes un-recoloured images, so run
recolor.py on them afterwards (python3 tools/recolor.py <src dir> <out dir>).
"""
import sys
from collections import Counter

import numpy as np
from PIL import Image

P = sys.argv[1] if len(sys.argv) > 1 else '.'

# name: (source, cell px, [left/right half for the two-shovel sheet], tool rotation
#        in degrees counter-clockwise (None = keep), longest side of the icon)
ICONS = {
    'twig':    ('src_twig.png', 34.46, None, None, 44),
    'log':     ('src_log.png', 25.52, None, None, 40),
    'axe':     ('src_axe.png', 12.51, None, -45, 38),
    'pickaxe': ('src_pickaxe.png', 29.6, None, -45, 40),
    'spade':   ('src_spade.png', 31.66, 'right', 135, 40),   # blade up, then tilted: blade top right
    'copper_ore': ('src_copper_ore.png', 33.0, None, None, 40),  # 36 x 27: already fits, kept 1:1
    'stone':   ('src_stone.png', 31.88, None, None, 40),             # 34 x 30, kept 1:1
    'watering_can': ('src_watering_can.png', 28.95, None, None, 40),  # upright (a can reads better than tilted)
}
# Map props from the same kind of source art, kept at native size (1 art px =
# 1 world px, like the other props): name -> (source, cell px). -> assets/props/<name>.png
PROP_ART = {
    'copper_node': ('src_copper_node.png', 26.36),
    'copper_node_small': ('src_copper_node_small.png', 27.56),   # small deposit
    'stone_node_a': ('src_stone_node_a.png', 25.54),   # wide, low pile
    'stone_node_b': ('src_stone_node_b.png', 25.35),   # tall slab with rubble
    'stone_node_c': ('src_stone_node_c.png', 26.36),   # round heap (same shape as the copper node)
}


def best_offset(alpha_edges, s):
    ang = (alpha_edges % s) / s * 2 * np.pi
    return (np.angle(np.exp(1j * ang).mean()) / (2 * np.pi) % 1) * s


def native(path, s):
    """Samples the centre of every grid cell -> native-resolution RGBA."""
    a = np.asarray(Image.open(path).convert('RGBA')).astype(int)
    rgb = a[..., :3] * (a[..., 3:] > 0)
    offs = []
    for axis in (1, 0):
        d = np.abs(np.diff(rgb, axis=axis)).sum(-1) > 60
        pos = np.nonzero(d.sum(axis=1 - axis) > 2)[0] + 1
        offs.append(best_offset(pos, s))
    ox, oy = offs
    h, w = a.shape[:2]
    nx, ny = int((w - ox) // s), int((h - oy) // s)
    cx = (ox + (np.arange(nx) + 0.5) * s).astype(int)
    cy = (oy + (np.arange(ny) + 0.5) * s).astype(int)
    out = a[cy][:, cx].astype(np.uint8)
    out[out[..., 3] < 128] = 0
    out[..., 3][out[..., 3] >= 128] = 255
    return crop(out)


def crop(a):
    ys, xs = np.nonzero(a[..., 3] > 0)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def scale2x(a):
    """Scale2x / EPX on an RGBA array (keeps pixel-art edges sharp)."""
    h, w = a.shape[:2]
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode='edge')
    B, D, F, H, E = p[:-2, 1:-1], p[1:-1, :-2], p[1:-1, 2:], p[2:, 1:-1], p[1:-1, 1:-1]
    eq = lambda x, y: (x == y).all(-1)[..., None]
    out = np.zeros((h * 2, w * 2, 4), np.uint8)
    out[0::2, 0::2] = np.where(eq(D, B) & ~eq(D, H) & ~eq(B, F), D, E)
    out[0::2, 1::2] = np.where(eq(B, F) & ~eq(B, D) & ~eq(F, H), F, E)
    out[1::2, 0::2] = np.where(eq(D, H) & ~eq(D, B) & ~eq(H, F), D, E)
    out[1::2, 1::2] = np.where(eq(H, F) & ~eq(H, D) & ~eq(F, B), F, E)
    return out


def rotsprite(a, deg):
    big = a
    for _ in range(3):
        big = scale2x(big)
    im = Image.fromarray(big, 'RGBA').rotate(deg, resample=Image.NEAREST, expand=True)
    return crop(np.asarray(im)), 8.0


def shrink(a, longest, unit=1.0):
    """Mode-downsample `a` (whose pixels are `unit` x native size) so its longest
    side is `longest` px. Transparent wins only if it covers half the block."""
    h, w = a.shape[:2]
    if unit == 1.0 and max(w, h) <= longest:
        return a                                   # already small enough: keep every pixel
    f = longest / max(w, h)
    ow, oh = max(1, round(w * f)), max(1, round(h * f))
    out = np.zeros((oh, ow, 4), np.uint8)
    for y in range(oh):
        y0, y1 = int(y / f), max(int((y + 1) / f), int(y / f) + 1)
        for x in range(ow):
            x0, x1 = int(x / f), max(int((x + 1) / f), int(x / f) + 1)
            blk = a[y0:y1, x0:x1].reshape(-1, 4)
            solid = blk[blk[:, 3] > 0]
            if len(solid) * 2 < len(blk):
                continue
            # Darkest colours (outlines) get a little extra weight so thin
            # outlines survive the shrink.
            cnt = Counter(map(tuple, solid))
            out[y, x] = max(cnt, key=lambda c: cnt[c] * (1.6 if sum(int(v) for v in c[:3]) < 160 else 1.0))
    return out


def outline_shrink(a, f, cover=0.25):
    """Shrink for thin pixel art (the twig): a pixel is solid if at least `cover`
    of its block is (so thin branches stay connected), filled with the most
    common NON-outline colour of the block, then a fresh 1 px dark outline is
    drawn around the whole silhouette. Keeps a thin branch readable at small
    sizes where the plain mode shrink breaks it into dots."""
    from scipy import ndimage
    h, w = a.shape[:2]
    ow, oh = round(w * f), round(h * f)
    op = a[..., 3] > 0
    cols = a[..., :3].astype(int)
    lum = cols[..., 0] * 0.3 + cols[..., 1] * 0.59 + cols[..., 2] * 0.11
    dark = op & (lum < 60)
    outline = Counter(map(tuple, cols[dark])).most_common(1)[0][0]
    out = np.zeros((oh, ow, 4), np.uint8)
    solid = np.zeros((oh, ow), bool)
    for y in range(oh):
        y0, y1 = int(y / f), max(int((y + 1) / f), int(y / f) + 1)
        for x in range(ow):
            x0, x1 = int(x / f), max(int((x + 1) / f), int(x / f) + 1)
            bo = op[y0:y1, x0:x1]
            if bo.mean() < cover:
                continue
            inner = cols[y0:y1, x0:x1][bo & ~dark[y0:y1, x0:x1]]
            if len(inner) == 0:
                inner = cols[y0:y1, x0:x1][bo]
            out[y, x, :3] = Counter(map(tuple, inner)).most_common(1)[0][0]
            out[y, x, 3] = 255
            solid[y, x] = True
    big = np.pad(out, ((1, 1), (1, 1), (0, 0)))
    s2 = np.pad(solid, 1)
    ring = ndimage.binary_dilation(s2, structure=[[0, 1, 0], [1, 1, 1], [0, 1, 0]]) & ~s2
    big[ring, :3] = outline
    big[ring, 3] = 255
    return big


for name, (src, cell, half, rot, longest) in ICONS.items():
    a = native(f'{P}/tools/art/{src}', cell)
    if half:
        mid = a.shape[1] // 2
        a = crop(a[:, mid:] if half == 'right' else a[:, :mid])
    Image.fromarray(a, 'RGBA').save(f'{P}/tools/art/native_{name}.png')
    unit = 1.0
    if rot is not None:
        a, unit = rotsprite(a, rot)
    if name == 'twig':
        icon = outline_shrink(a, 0.5)              # thin branch: see outline_shrink
    else:
        icon = shrink(a, longest, unit if rot is not None else 1.0)
    Image.fromarray(icon, 'RGBA').save(f'{P}/assets/ui/{name}.png')
    print(name, 'native', a.shape[1::-1] if rot is None else '', '-> icon', icon.shape[1], 'x', icon.shape[0])

for name, (src, cell) in PROP_ART.items():
    a = native(f'{P}/tools/art/{src}', cell)
    Image.fromarray(a, 'RGBA').save(f'{P}/assets/props/{name}.png')
    print(name, 'prop', a.shape[1], 'x', a.shape[0])

# The old stick and fallen-log map art is replaced by the same new art:
#   assets/props/stick.png = the twig, shrunk to stick size (pickable sticks on the map,
#                            and how dropped twigs look)
#   assets/props/log.png   = the log at native size (the fallen logs in the forest)
#   assets/props/log_drop.png = dropped logs (40 px)
# (the old images are kept as tools/art/old_stick.png / old_log.png)
twig = np.asarray(Image.open(f'{P}/tools/art/native_twig.png').convert('RGBA'))
Image.fromarray(outline_shrink(twig, 0.34, 0.2), 'RGBA').save(f'{P}/assets/props/stick.png')
log = np.asarray(Image.open(f'{P}/tools/art/native_log.png').convert('RGBA'))
Image.fromarray(log, 'RGBA').save(f'{P}/assets/props/log.png')
# Dropped logs: the 40 px icon art at 1:1 (own file name, so nothing mistakes a
# dropped log for a fallen-log prop).
Image.open(f'{P}/assets/ui/log.png').save(f'{P}/assets/props/log_drop.png')
print('map stick', Image.open(f'{P}/assets/props/stick.png').size, 'map log', log.shape[1::-1])

# Mouse cursor (scripts/main.gd sets it): native pixels, plus a 2x copy for big
# screens. The hotspot (the arrow's tip) is printed for main.gd.
cur = native(f'{P}/tools/art/src_cursor.png', 26.89)
Image.fromarray(cur, 'RGBA').save(f'{P}/assets/ui/cursor.png')
Image.fromarray(cur, 'RGBA').resize((cur.shape[1] * 2, cur.shape[0] * 2), Image.NEAREST).save(f'{P}/assets/ui/cursor_2x.png')
ys, xs = np.nonzero(cur[..., 3] > 0)
top = ys.min()
print('cursor', cur.shape[1::-1], 'tip', (int(xs[ys == top].min()), int(top)))
