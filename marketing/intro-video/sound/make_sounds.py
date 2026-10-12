"""Makes the film's air-and-motion sound effects, the ones the CC0 Kenney packs (public/sfx/kenney) don't cover.
No samples, so no licences. Run: python3 sound/make_sounds.py  →  public/sfx/{whoosh,swoosh,rise,roll}.wav"""
import os
import wave
import numpy as np

SR = 48000
OUT = os.path.join(os.path.dirname(__file__), '..', 'public', 'sfx')
rng = np.random.default_rng(7)


def t_of(seconds):
    return np.arange(int(seconds * SR)) / SR


def band(x, low=0.0, high=SR / 2):
    """Frequency-domain filter with soft edges."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    gain = np.ones_like(f)
    if high < SR / 2:
        gain *= 1 / (1 + (f / high) ** 4)
    if low > 0:
        gain *= 1 / (1 + (low / np.maximum(f, 1)) ** 4)
    return np.fft.irfft(spec * gain, len(x))


def swept_noise(seconds, low, cutoff, chunk=1200):
    """Noise whose upper cutoff follows `cutoff(progress)`, filtered in short chunks."""
    n = rng.standard_normal(int(seconds * SR))
    out = np.zeros_like(n)
    for i in range(0, len(n), chunk):
        out[i:i + chunk] = band(n[i:i + chunk], low, cutoff(i / len(n)))
    return out


def whoosh():  # something big moving past the camera
    t = t_of(0.6)
    return swept_noise(0.6, 150, lambda p: 500 + 5000 * np.sin(np.pi * p), 2400) * np.sin(np.pi * t / 0.6) ** 2


def swoosh():  # words or a scene arriving: short and airy
    t = t_of(0.28)
    return swept_noise(0.28, 800, lambda p: 2000 + 9000 * p) * np.sin(np.pi * t / 0.28) ** 1.5


def rise():  # a ring or bars filling: a quick tonal lift
    t = t_of(0.55)
    f = 300 * 2 ** (2 * t / 0.55)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * np.sin(2 * np.pi * np.cumsum(2 * f) / SR)
    return tone * np.sin(np.pi * t / 0.55) * 0.8


def roll():  # a number counting up: ticks that slow down as it settles
    t = t_of(0.06)
    tick = (np.sin(2 * np.pi * 2600 * t) * 0.6 + np.sin(2 * np.pi * 3900 * t) * 0.3) * np.exp(-t * 100)
    out = np.zeros(int(1.1 * SR))
    at, gap = 0.0, 0.025
    while at < 1.0:
        i = int(at * SR)
        out[i:i + len(tick)] += tick[: len(out) - i] * (0.5 + 0.5 * at)
        at += gap
        gap *= 1.09
    return out


def write(name, mono, gain):
    data = (mono / (np.max(np.abs(mono)) or 1) * gain * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(np.repeat(data[:, None], 2, axis=1).tobytes())


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    write('whoosh.wav', whoosh(), 0.7)
    write('swoosh.wav', swoosh(), 0.55)
    write('rise.wav', rise(), 0.45)
    write('roll.wav', roll(), 0.45)
    print('ok')
