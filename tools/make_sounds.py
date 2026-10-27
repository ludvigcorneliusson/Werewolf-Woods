"""Synthesizes the placeholder chopping sounds in assets/sounds/:
  chop.wav       - a woody knock for each axe hit
  tree_fall.wav  - a deep thud with a leafy rustle, played when a tree lands
  mine_hit.wav   - pick on rock: a stony knock with a short metallic ring
  rock_break.wav - an ore node crumbling: rubble rattling over a low thud
Usage: python3 tools/make_sounds.py <project folder>"""
import sys, wave
import numpy as np

P = sys.argv[1] if len(sys.argv) > 1 else '.'
sr = 44100
rng = np.random.default_rng(7)


def save(path, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.9
    w = wave.open(path, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes((x * 32767).astype(np.int16).tobytes()); w.close()


def lowpass(x, a):
    y = np.zeros_like(x); acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc); y[i] = acc
    return y


# Chop: sharp click + woody knock (damped resonances) + short noise.
t = np.arange(int(sr * 0.35)) / sr
knock = (np.sin(2*np.pi*180*t) * np.exp(-t*28) * 0.9 + np.sin(2*np.pi*410*t) * np.exp(-t*45) * 0.6
         + np.sin(2*np.pi*930*t) * np.exp(-t*70) * 0.35)
noise = lowpass(rng.standard_normal(len(t)), 0.35) * np.exp(-t*60) * 0.8
click = rng.standard_normal(len(t)) * np.exp(-t*900) * 0.6
save(f'{P}/assets/sounds/chop.wav', knock + noise + click)

# Tree landing: low thud + a short crunch + branches rustling (no rising tone).
t = np.arange(int(sr * 0.9)) / sr
thud = np.sin(2*np.pi*52*t) * np.exp(-t*7) * 1.2 + np.sin(2*np.pi*88*t) * np.exp(-t*11) * 0.6
crunch = lowpass(rng.standard_normal(len(t)), 0.5) * np.exp(-t*30) * 0.7
rustle = lowpass(rng.standard_normal(len(t)), 0.22) * np.exp(-t*4.5) * 0.45
save(f'{P}/assets/sounds/tree_fall.wav', thud + crunch + rustle)
# Pick on rock: hard click, dull stone knock, short bright ring (inharmonic partials).
t = np.arange(int(sr * 0.4)) / sr
ring = sum(np.sin(2*np.pi*f*t) * np.exp(-t*d) * a for f, d, a in
           [(1870, 22, 0.5), (2710, 30, 0.35), (4130, 45, 0.25), (5390, 60, 0.15)])
stone = np.sin(2*np.pi*240*t) * np.exp(-t*55) * 0.8 + lowpass(rng.standard_normal(len(t)), 0.6) * np.exp(-t*80) * 0.7
click = rng.standard_normal(len(t)) * np.exp(-t*1500) * 0.9
save(f'{P}/assets/sounds/mine_hit.wav', ring + stone + click)

# Rock crumbling: a low thud, then many small stone knocks rattling down.
t = np.arange(int(sr * 1.0)) / sr
x = np.sin(2*np.pi*60*t) * np.exp(-t*9) * 1.0 + lowpass(rng.standard_normal(len(t)), 0.45) * np.exp(-t*12) * 0.6
for k in range(38):
    t0 = rng.uniform(0.0, 0.6) ** 1.6
    i0 = int(t0 * sr)
    tt = t[: len(t) - i0]
    f = rng.uniform(500, 1600)
    x[i0:] += (np.sin(2*np.pi*f*tt) * np.exp(-tt*rng.uniform(60, 120)) + rng.standard_normal(len(tt)) * np.exp(-tt*400) * 0.6) \
        * rng.uniform(0.15, 0.4) * np.exp(-t0*2.5)
save(f'{P}/assets/sounds/rock_break.wav', x)


def biquad_bp(x, f0, q):
    """Band-pass with a centre frequency that can change per sample (f0 array)."""
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        w = 2 * np.pi * f0[i] / sr
        al = np.sin(w) / (2 * q)
        b0, b2 = al, -al
        a0, a1, a2 = 1 + al, -2 * np.cos(w), 1 - al
        yi = (b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1 = x1, x[i]
        y2, y1 = y1, yi
        y[i] = yi
    return y


def save_at(path, x, peak):
    x = x / max(np.abs(x).max(), 1e-6) * peak
    w = wave.open(path, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes((x * 32767).astype(np.int16).tobytes()); w.close()


# (Footstep sounds were removed - the synthesized ones did not work out.)


# (Tool swing whooshes were removed.)

print('sounds written')
