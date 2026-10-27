"""Builds assets/props/pine_tall_stump.png: the bottom of pine_tall.png below the
cut row, with a cut face (tree rings) on top, borrowed from the hand-drawn
stump art (tools/art/stump_face_source.png) and fitted to the pine's trunk.
Same 90x166 canvas as pine_tall.png, so it lines up exactly with the tree (the
scene uses the same sprite offset). Usage:
  python3 tools/make_pine_stump.py <project folder> [cut row]"""
import sys
import numpy as np
from PIL import Image

P = sys.argv[1] if len(sys.argv) > 1 else '.'
CUT = int(sys.argv[2]) if len(sys.argv) > 2 else 145
tree = np.asarray(Image.open(f'{P}/assets/props/pine_tall.png').convert('RGBA')).copy()
src = np.asarray(Image.open(f'{P}/tools/art/stump_face_source.png').convert('RGBA'))

# The face = the top rows of the source stump down to where its sides go straight.
FACE_ROWS = 6
face = src[:FACE_ROWS]
fa = face[..., 3] > 128
fx = np.where(fa.any(0))[0]
face = face[:, fx.min():fx.max() + 1]
fa = fa[:, fx.min():fx.max() + 1]

# Trunk at the cut row (brown pixels).
row = tree[CUT]
brown = np.where((row[:, 3] > 128) & (row[:, 0].astype(int) > row[:, 1].astype(int) + 15))[0]
t0, t1 = brown.min(), brown.max()
tw = t1 - t0 + 1
# Fit the face to the trunk width (nearest-neighbour, keeps the pixel look).
fw = face.shape[1]
xs = np.clip((np.arange(tw) * fw / tw).astype(int), 0, fw - 1)
face = face[:, xs]
fa = fa[:, xs]

out = np.zeros_like(tree)
out[CUT:] = tree[CUT:]
# Face sits with its lower rim on the cut row (the rim covers the cut edge).
top = CUT - (FACE_ROWS - 2)
for y in range(FACE_ROWS):
    for x in range(tw):
        if fa[y, x]:
            out[top + y, t0 + x] = face[y, x]
Image.fromarray(out, 'RGBA').save(f'{P}/assets/props/pine_tall_stump.png')
print(f'cut={CUT} trunk x {t0}..{t1} face top row {top}')
