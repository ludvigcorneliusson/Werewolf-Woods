"""Synthesizes the placeholder chopping sounds in assets/sounds/:
  chop.wav       - a woody knock for each axe hit
  tree_fall.wav  - a deep thud with a leafy rustle, played when a tree lands
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
print('sounds written')
