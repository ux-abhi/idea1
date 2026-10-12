"""Makes the intro's soundtrack from scratch (no samples, so no licences): a 60 s music bed at 120 BPM
and short interface sounds. Run: python3 sound/make_sounds.py  →  public/sfx/*.wav"""
import os
import wave
import numpy as np

SR = 48000
BEAT = 0.5  # 120 BPM
OUT = os.path.join(os.path.dirname(__file__), '..', 'public', 'sfx')
rng = np.random.default_rng(7)


def t_of(seconds):
    return np.arange(int(seconds * SR)) / SR


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def lowpass(x, cutoff):
    # One-pole low-pass: soft and warm, enough for pads and noise.
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def write(name, mono, gain=0.9):
    peak = np.max(np.abs(mono)) or 1
    data = (mono / peak * gain * 32767).astype(np.int16)
    stereo = np.repeat(data[:, None], 2, axis=1)
    with wave.open(os.path.join(OUT, name), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(stereo.tobytes())


def add(track, start, sound):
    i = int(start * SR)
    end = min(len(track), i + len(sound))
    track[i:end] += sound[: end - i]


# --- Instruments ---------------------------------------------------------------------------------

def pad_note(midi, seconds):
    t = t_of(seconds)
    f = hz(midi)
    tone = sum(np.sin(2 * np.pi * f * d * t) for d in (0.997, 1.0, 1.003)) / 3
    tone += 0.25 * np.sin(2 * np.pi * 2 * f * t)
    env = np.minimum(1, t / 0.8) * np.minimum(1, (seconds - t) / 0.6)
    return tone * env


def pluck(midi, seconds=0.6):
    t = t_of(seconds)
    f = hz(midi)
    tone = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t) + 0.1 * np.sin(2 * np.pi * 3 * f * t)
    return tone * np.exp(-t * 7) * np.minimum(1, t / 0.004)


def kick():
    t = t_of(0.35)
    sweep = 45 + 110 * np.exp(-t * 30)
    phase = 2 * np.pi * np.cumsum(sweep) / SR
    return np.sin(phase) * np.exp(-t * 9)


def hat():
    t = t_of(0.06)
    n = rng.standard_normal(len(t))
    n = n - lowpass(n, 6000)  # keep the highs
    return n * np.exp(-t * 70)


def bell(midi, seconds=2.0):
    t = t_of(seconds)
    f = hz(midi)
    partials = [(1, 1.0, 2.2), (2.0, 0.5, 3.0), (2.76, 0.35, 4.5), (5.4, 0.12, 7)]
    return sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * d) for r, a, d in partials) * np.minimum(1, t / 0.003)


# --- Music bed ---------------------------------------------------------------------------------

# Where the film's scenes start (seconds); keep in step with src/BlinkIntro.tsx.
SECTIONS = {'hook': 3.5, 'meet': 7.0, 'ask': 12.0, 'clipboard': 29.0, 'clipboard_drop_ends': 31.0,
            'burst': 50.0, 'private': 53.0, 'end': 56.0}
TOTAL = 60.0


def music():
    track = np.zeros(int(TOTAL * SR))
    # D major, warm and hopeful: Dmaj9, Bm9, Gmaj7, Asus4; two bars (4 s) each.
    chords = [
        [50, 57, 61, 64, 66],  # Dmaj9
        [47, 54, 57, 61, 62],  # Bm9 (B D F# A C#)
        [43, 50, 54, 59, 62],  # Gmaj7
        [45, 52, 55, 57, 62],  # Asus4
    ]
    s = SECTIONS
    for bar in range(int(TOTAL / 4)):
        start = bar * 4.0
        chord = chords[bar % 4]
        length = min(4.4, TOTAL - start)
        for m in chord:
            add(track, start, 0.06 * pad_note(m + 12, length))
        # Arpeggio from the hook on: eighth notes over the chord, an octave up.
        for step in range(16):
            at = start + step * BEAT / 2
            if s['hook'] <= at < s['end']:
                note = chord[1:][[0, 1, 2, 3, 2, 1, 3, 2][step % 8]] + 24
                add(track, at, 0.05 * pluck(note))
    for b in range(int(TOTAL / BEAT)):
        at = b * BEAT
        drop = s['clipboard'] <= at < s['clipboard_drop_ends']  # a one-bar breath as the clipboard opens
        if s['meet'] <= at < s['private'] and not drop:
            add(track, at, 0.32 * kick())
        if s['ask'] <= at < s['private'] and not drop:
            add(track, at + BEAT / 2, 0.05 * hat())
        if s['burst'] <= at < s['private']:  # sixteenths for the rapid-fire list
            add(track, at + BEAT / 4, 0.035 * hat())
            add(track, at + 3 * BEAT / 4, 0.035 * hat())
    # The ending: one bright chord and a bell on the wordmark, then fade.
    for m in [62, 69, 73, 76, 78]:
        add(track, s['end'], 0.05 * pad_note(m, TOTAL - s['end']))
    add(track, s['end'], 0.12 * bell(86, 3.0))
    t = t_of(TOTAL)
    fade = np.minimum(1, t / 1.5) * np.minimum(1, (TOTAL - t) / 1.5)
    return lowpass(track * fade, 9000)


# --- Interface sounds ------------------------------------------------------------------------------

def tick():  # a word landing: soft, glassy
    t = t_of(0.05)
    return (np.sin(2 * np.pi * 2400 * t) * 0.6 + np.sin(2 * np.pi * 3600 * t) * 0.3) * np.exp(-t * 120)


def key():  # one keystroke
    t = t_of(0.03)
    n = rng.standard_normal(len(t))
    n = n - lowpass(n, 3000)
    return n * np.exp(-t * 200)


def whoosh():  # air moving past, for big moves
    t = t_of(0.7)
    n = rng.standard_normal(len(t))
    env = np.sin(np.pi * np.minimum(1, t / 0.7)) ** 2
    return lowpass(n, 1800) * env


def tap():  # the notch opening, Touch ID: a soft low press
    t = t_of(0.25)
    return np.sin(2 * np.pi * (90 + 60 * np.exp(-t * 40)) * t) * np.exp(-t * 18)


def chime():  # done / approved: two bright notes
    a = bell(81, 1.4)
    b = bell(88, 1.2)
    out = np.zeros(len(a))
    out += a
    out[int(0.09 * SR): int(0.09 * SR) + len(b)] += b[: len(out) - int(0.09 * SR)]
    return out


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    write('music.wav', music(), 0.8)
    write('tick.wav', tick(), 0.5)
    write('key.wav', key(), 0.4)
    write('whoosh.wav', whoosh(), 0.6)
    write('tap.wav', tap(), 0.8)
    write('chime.wav', chime(), 0.6)
    print('ok')
