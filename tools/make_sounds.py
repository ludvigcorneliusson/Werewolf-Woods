"""Synthesizes the placeholder chopping sounds in assets/sounds/:
  chop.wav       - a woody knock for each axe hit
  tree_fall.wav  - a deep thud with a leafy rustle, played when a tree lands
  mine_hit.wav   - pick on rock: a stony knock with a short metallic ring
  rock_break.wav - an ore node crumbling: rubble rattling over a low thud
  footsteps/grass_soft_1-3.wav - the settler's soft grass steps (three takes, cycled)
  footsteps/werewolf_step.wav  - the werewolf's heavier paw step
  swing_axe / swing_pickaxe / swing_spade / swing_can.wav - tool swing whooshes
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


# Soft grass steps: a dense crunch of tiny blade snaps (heel, then a smaller toe
# roll) through a band-pass, over a very soft low thud. Three takes so walking
# doesn't sound like one sample on repeat.
for take in range(1, 4):
    r = np.random.default_rng(100 + take)
    t = np.arange(int(sr * 0.22)) / sr
    x = np.zeros_like(t)
    for start, length, count, amp in [(0.0, 0.07, 46, 1.0), (0.075, 0.06, 26, 0.55)]:
        for k in range(count):
            t0 = start + r.uniform(0, length) ** 1.3 * length ** -0.3
            i0 = int(t0 * sr)
            n = int(sr * r.uniform(0.0008, 0.003))
            if i0 + n >= len(x):
                continue
            x[i0:i0 + n] += r.standard_normal(n) * np.exp(-np.arange(n) / (n * 0.3)) * amp * r.uniform(0.3, 1.0)
    crunch = biquad_bp(x, np.full(len(x), r.uniform(2600, 3400)), 0.7)
    thud = lowpass(r.standard_normal(len(t)), 0.03) * np.exp(-t * 45) * 3.0
    step = crunch + thud
    step *= np.minimum(1.0, t / 0.003)                    # no click at the start
    step *= np.clip((0.22 - t) / 0.03, 0, 1)              # fade the tail
    save_at(f'{P}/assets/sounds/footsteps/grass_soft_{take}.wav', step, 0.55)


# Werewolf: a heavier paw - deeper thud, lower, coarser crunch.
r = np.random.default_rng(200)
t = np.arange(int(sr * 0.3)) / sr
x = np.zeros_like(t)
for k in range(40):
    t0 = r.uniform(0, 0.09)
    i0 = int(t0 * sr)
    n = int(sr * r.uniform(0.002, 0.006))
    x[i0:i0 + n] += r.standard_normal(n) * np.exp(-np.arange(n) / (n * 0.3)) * r.uniform(0.3, 1.0)
crunch = biquad_bp(x, np.full(len(x), 1500.0), 0.6)
thud = np.sin(2 * np.pi * 70 * t) * np.exp(-t * 30) * 1.6 + lowpass(r.standard_normal(len(t)), 0.04) * np.exp(-t * 25) * 2.5
w = (crunch + thud) * np.minimum(1.0, t / 0.002) * np.clip((0.3 - t) / 0.05, 0, 1)
save_at(f'{P}/assets/sounds/footsteps/werewolf_step.wav', w, 0.7)


# Swing whooshes: noise through a band-pass sweeping up (the tool speeding
# up), loudest just before the hit. Per tool: (seconds, start Hz, end Hz, Q, extra).
def whoosh(dur, f_a, f_b, q, seed):
    r = np.random.default_rng(seed)
    t = np.arange(int(sr * dur)) / sr
    u = t / dur
    f0 = f_a * (f_b / f_a) ** (u ** 1.6)
    x = biquad_bp(r.standard_normal(len(t)), f0, q)
    env = np.sin(np.pi * np.clip(u, 0, 1) ** 1.8) ** 2     # swells, peaks late, dies fast
    return x * env, t

x, t = whoosh(0.30, 450, 1500, 1.2, 11)
save_at(f'{P}/assets/sounds/swing_axe.wav', x, 0.5)
x, t = whoosh(0.36, 260, 900, 1.0, 12)                     # heavier pick: lower, longer
x += lowpass(np.random.default_rng(13).standard_normal(len(t)), 0.05) * np.sin(np.pi * t / t[-1]) ** 3 * 2.0
save_at(f'{P}/assets/sounds/swing_pickaxe.wav', x, 0.55)
x, t = whoosh(0.24, 700, 2000, 1.4, 14)                    # spade: quick, lighter
save_at(f'{P}/assets/sounds/swing_spade.wav', x, 0.4)
x, t = whoosh(0.32, 380, 800, 0.9, 15)                     # can: soft swish + water sloshing inside
r = np.random.default_rng(16)
for k in range(9):
    t0 = r.uniform(0.08, 0.26)
    i0 = int(t0 * sr)
    tt = t[: len(t) - i0]
    f = r.uniform(260, 620)
    x[i0:] += np.sin(2 * np.pi * (f + 900 * tt) * tt) * np.exp(-tt * r.uniform(35, 60)) * r.uniform(0.15, 0.35)
save_at(f'{P}/assets/sounds/swing_can.wav', x, 0.35)
print('sounds written')
