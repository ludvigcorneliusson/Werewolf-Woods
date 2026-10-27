"""Draws the small pixel-art UI icons (assets/ui/): axe (tools bar) and heart
(health bar). Colours come from the settler's palette and the chop strip's axe
greys so they match the game art. Usage: python3 tools/make_ui_icons.py <project>"""
import sys
import numpy as np
from PIL import Image

P = sys.argv[1] if len(sys.argv) > 1 else '.'
strip = np.asarray(Image.open(f'{P}/assets/characters/settler_chop_right.png').convert('RGBA')).reshape(-1, 4)
cols = np.unique(strip[strip[:, 3] > 128][:, :3], axis=0).astype(int)
sat = cols.max(1).astype(int) - cols.min(1)
greys = sorted([tuple(c) for c, s in zip(cols, sat) if s < 28 and c.mean() > 70], key=lambda c: sum(c))
dark = tuple(cols[np.argmin(cols.sum(1))])
G = {'o': dark, 'g': greys[len(greys) // 2] if greys else (150, 150, 150),
     'h': greys[-1] if greys else (210, 210, 210), 's': greys[0] if greys else (110, 110, 110),
     'w': (146, 98, 62), 'd': (104, 68, 44), 'l': (184, 132, 86)}   # wood

AXE = """
...........ooo..
..........ohhho.
.........ohhggso
........oohgggso
.......owoogggso
......owdo.oggso
.....owdo...ooo.
....owlo........
...owdo.........
..owlo..........
.owdo...........
.odo............
..o.............
"""
HEART = """
.oo...oo.
orro.orro
orhrorrro
orhrrrrro
orrrrrrdo
.orrrrdo.
..orrdo..
...odo...
....o....
"""


def draw(art, pal):
    rows = [r for r in art.strip('\n').split('\n')]
    h, w = len(rows), max(len(r) for r in rows)
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in pal:
                im.putpixel((x, y), tuple(pal[ch]) + (255,))
    return im


# assets/ui/axe.png now comes from tools/make_item_icons.py (the user's axe art).
# draw(AXE, G).save(f'{P}/assets/ui/axe.png')
heart_pal = {'o': dark, 'r': (196, 52, 46), 'd': (140, 32, 34), 'h': (240, 140, 120)}
draw(HEART, heart_pal).save(f'{P}/assets/ui/heart.png')

# Upgrade icons (level-up cards).
FAST_AXE = """
................
..y........ooo..
.y..y.....ohhho.
y..y.....ohhggso
..y.....oohgggso
.y.....owoogggso
......owdo.oggso
.....owdo...ooo.
....owlo........
...owdo.........
..owlo..........
.owdo...........
.odo............
..o.............
"""
BOOT = """
................
.....oooooo.....
.....ottttdo....
.....ottttdo....
.....ottttdo....
y....ottttdo....
.y...otttttdo...
yy...ottttttdoo.
.....otttttttddo
..y..ollllllllto
.y...oddddddddo.
.....oooooooooo.
"""
STRONG_AXE = """
......y.........
...y..y..yooo...
....y.y.yohhho..
.....yyyohhggso.
.yyyyyy.oohgggso
.....yyyowoogggso
....y.yowdo.oggso
...y..owdo...ooo.
.....owlo........
....owdo.........
...owlo..........
..owdo...........
..odo............
...o.............
"""
up = dict(G)
up['y'] = (250, 214, 110)
up['t'] = (122, 82, 58)
up['l'] = (184, 132, 86)
draw(FAST_AXE, up).save(f'{P}/assets/ui/up_chop_speed.png')
draw(BOOT, up).save(f'{P}/assets/ui/up_run_speed.png')
draw(STRONG_AXE, up).save(f'{P}/assets/ui/up_axe_damage.png')
print('icons written')
