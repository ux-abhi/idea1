"""Makes the film's soundtrack from scratch (no samples, so no licences): a 60 s energetic track at 120 BPM and
short interface sounds. Run: python3 sound/make_sounds.py  →  public/sfx/*.wav

Arrangement follows the film's scenes (SECTIONS, in seconds; keep in step with src/BlinkIntro.tsx):
intro swell → impact on the hook → build → drop on "Meet Blink" → full groove → one-bar breakdown and drop as the
clipboard opens → groove with an extra layer from Money on → roll into the feature list (double-time) →
breakdown for privacy → final impact and chord on the wordmark."""
import os
import wave
import numpy as np

SR = 48000
BEAT = 0.5  # 120 BPM: cuts in the film land on beats
TOTAL = 60.0
SECTIONS = {
    'hook': 3.5, 'meet': 7.0, 'ask': 12.0, 'clipboard': 26.5, 'clipboard_drop': 28.5,
    'money': 41.5, 'burst': 52.0, 'private': 54.5, 'end': 57.0,
}
OUT = os.path.join(os.path.dirname(__file__), '..', 'public', 'sfx')
rng = np.random.default_rng(7)


# --- Building blocks -----------------------------------------------------------------------------

def t_of(seconds):
    return np.arange(int(seconds * SR)) / SR


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def band(x, low=0.0, high=SR / 2):
    """Frequency-domain filter with soft edges: fast in numpy, fine for short notes and whole stems."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    gain = np.ones_like(f)
    if high < SR / 2:
        gain *= 1 / (1 + (f / high) ** 4)
    if low > 0:
        gain *= 1 / (1 + (low / np.maximum(f, 1)) ** 4)
    return np.fft.irfft(spec * gain, len(x))


def saw(f, t):
    return 2 * ((f * t) % 1.0) - 1


def add(track, start, sound, gain=1.0):
    i = int(round(start * SR))
    if i >= len(track):
        return
    end = min(len(track), i + len(sound))
    track[i:end] += gain * sound[: end - i]


def noise(seconds):
    return rng.standard_normal(int(seconds * SR))


# --- Instruments ---------------------------------------------------------------------------------

def kick():
    t = t_of(0.45)
    sweep = 48 + 140 * np.exp(-t * 28)
    body = np.sin(2 * np.pi * np.cumsum(sweep) / SR) * np.exp(-t * 6.5)
    click = band(noise(0.45), 1500, 6000) * np.exp(-t * 400) * 0.6
    return np.tanh(2.2 * (body + click)) / np.tanh(2.2)


def clap():
    t = t_of(0.3)
    n = band(noise(0.3), 900, 4000)
    env = np.zeros_like(t)
    for d in (0.0, 0.011, 0.022):
        env += np.where(t >= d, np.exp(-(t - d) * 90), 0)
    env += np.exp(-t * 14) * 0.5
    return n * env


def hat(open_=False):
    length = 0.25 if open_ else 0.06
    t = t_of(length)
    return band(noise(length), 7000) * np.exp(-t * (14 if open_ else 80))


def snare():
    t = t_of(0.2)
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30)
    return 0.5 * tone + band(noise(0.2), 1200, 9000) * np.exp(-t * 22)


def bass(midi, seconds):
    t = t_of(seconds)
    f = hz(midi)
    tone = 0.7 * saw(f, t) + 0.8 * np.sin(2 * np.pi * f * t)
    tone = band(tone, high=700)
    env = np.minimum(1, t / 0.004) * np.exp(-t * 6)
    return tone * env


def supersaw(notes, seconds, cutoff=4000, attack=0.008, decay=None):
    t = t_of(seconds)
    out = np.zeros_like(t)
    for m in notes:
        f = hz(m)
        for d in (-0.012, -0.007, -0.003, 0, 0.003, 0.007, 0.012):
            out += saw(f * (1 + d), t + rng.random() / f)
    out = band(out / (7 * len(notes)), 120, cutoff)
    env = np.minimum(1, t / attack) * np.minimum(1, (seconds - t) / 0.03)
    if decay:
        env *= np.exp(-t * decay)
    return out * env


def sub(midi, seconds, decay=0.0):
    t = t_of(seconds)
    return np.sin(2 * np.pi * hz(midi) * t) * np.exp(-t * decay) * np.minimum(1, t / 0.01) * np.minimum(1, (seconds - t) / 0.02)


def pluck(midi, seconds=0.25):
    t = t_of(seconds)
    f = hz(midi)
    sq = np.sign(np.sin(2 * np.pi * f * t)) * 0.5 + saw(f * 1.003, t) * 0.5
    return band(sq, high=6000) * np.exp(-t * 14) * np.minimum(1, t / 0.002)


def riser(seconds):
    t = t_of(seconds)
    p = t / seconds
    # Noise that opens up as it rises, done in short chunks with a rising cutoff.
    n = noise(seconds)
    out = np.zeros_like(n)
    chunk = 2400
    for i in range(0, len(n), chunk):
        cut = 600 + 9000 * (i / len(n)) ** 2
        out[i:i + chunk] = band(n[i:i + chunk], 200, cut)
    sweep = np.sin(2 * np.pi * np.cumsum(200 + 1800 * p ** 2) / SR) * 0.25
    return (out + sweep) * p ** 2.2


def impact():
    t = t_of(2.2)
    boom = np.sin(2 * np.pi * np.cumsum(30 + 45 * np.exp(-t * 3)) / SR) * np.exp(-t * 2.2)
    crash = band(noise(2.2), 300, 9000) * np.exp(-t * 2.8) * 0.5
    return np.tanh(1.8 * (boom + crash)) + 0.6 * np.pad(kick(), (0, len(t) - len(kick())))


def bell(midi, seconds=2.5):
    t = t_of(seconds)
    f = hz(midi)
    partials = [(1, 1.0, 2.0), (2.0, 0.5, 3.0), (2.76, 0.35, 4.5), (5.4, 0.12, 7)]
    return sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * d) for r, a, d in partials) * np.minimum(1, t / 0.003)


# --- The track -------------------------------------------------------------------------------------

# vi–IV–I–V in D (Bm, G, D, A), one bar (2 s) each: anthemic and forward-moving.
CHORDS = [[59, 62, 66], [55, 59, 62], [57, 62, 66], [57, 61, 64]]
ROOTS = [35, 31, 38, 33]


def chord_at(seconds):
    return int(seconds // 2) % 4


def music():
    n = int(TOTAL * SR)
    drums, synths, fx = np.zeros(n), np.zeros(n), np.zeros(n)
    s = SECTIONS

    def full(at):  # the full groove plays here
        return (s['meet'] <= at < s['clipboard']) or (s['clipboard_drop'] <= at < s['private'])

    kicks = []
    for b in range(int(TOTAL / BEAT)):
        at = b * BEAT
        bar_beat = b % 4
        c = chord_at(at)
        if full(at):
            kicks.append(at)
            add(drums, at, kick(), 0.95)
            if bar_beat in (1, 3):
                add(drums, at, clap(), 0.55)
            add(drums, at + BEAT / 2, hat(open_=True), 0.16)
            for k in range(4):
                add(drums, at + k * BEAT / 4, hat(), 0.09 if k % 2 else 0.05)
            # Driving sixteenth bass, octave jump on the last one.
            for k in range(4):
                add(synths, at + k * BEAT / 4, bass(ROOTS[c] + (12 if k == 3 else 0), BEAT / 4), 0.55)
            # Offbeat supersaw stabs.
            add(synths, at + BEAT / 2, supersaw(CHORDS[c], 0.2, cutoff=5000, decay=9), 0.42)
            if at >= s['ask']:  # arpeggio lead from Ask on; brighter (an octave up) from Money on
                up = 24 if at >= s['money'] else 12
                for k in range(2):
                    add(synths, at + k * BEAT / 2, pluck(CHORDS[c][(b * 2 + k) % 3] + up), 0.16)
        elif s['hook'] <= at < s['meet']:  # the build: half-time kick, eighth bass
            if bar_beat in (0, 2):
                kicks.append(at)
                add(drums, at, kick(), 0.8)
            for k in range(2):
                add(synths, at + k * BEAT / 2, bass(ROOTS[c], BEAT / 2), 0.45)
            add(synths, at, supersaw(CHORDS[c], BEAT, cutoff=1500 + 3000 * (at - s['hook']) / 3.5), 0.25)
        if s['burst'] <= at < s['private']:  # double-time snare on top of the groove
            add(drums, at, snare(), 0.35)
            add(drums, at + BEAT / 2, snare(), 0.35)

    # Pads where the groove rests: the intro, the clipboard breath, privacy, the ending.
    for a, z, cut in ((0, s['hook'], 1800), (s['clipboard'], s['clipboard_drop'], 2500), (s['private'], s['end'], 2200)):
        at = a
        while at < z:
            seg = min(2.0 - at % 2.0, z - at)
            add(synths, at, supersaw(CHORDS[chord_at(at)], seg, cutoff=cut, attack=0.3), 0.35)
            add(synths, at, sub(ROOTS[chord_at(at)], seg), 0.18)
            at += seg

    # Builds: rolls and risers into every big moment, then an impact.
    def roll(start, end):
        at, step = start, BEAT / 2
        while at < end - 1e-6:
            p = (at - start) / (end - start)
            add(drums, at, snare(), 0.18 + 0.3 * p)
            step = BEAT / 2 if p < 0.5 else BEAT / 4 if p < 0.8 else BEAT / 8
            at += step

    for hit, build in ((s['hook'], 2.0), (s['meet'], 2.0), (s['clipboard_drop'], 2.0), (s['burst'], 1.5), (s['end'], 2.0)):
        add(fx, hit - build, riser(build), 0.35)
        if hit != s['hook']:
            roll(hit - build, hit)
        add(fx, hit, impact(), 0.7)

    # The ending: a big held chord, a bell, and the tail.
    end_len = TOTAL - s['end']
    add(synths, s['end'], supersaw([62, 66, 69, 74], end_len, cutoff=6000, attack=0.01, decay=0.6), 0.6)
    add(synths, s['end'], sub(38, end_len, decay=0.9), 0.5)
    add(fx, s['end'], bell(86, 3.0), 0.25)

    # Sidechain: synths duck under every kick, the "pump" of energetic electronic music.
    duck = np.ones(n)
    tt = t_of(0.3)
    shape = 1 - 0.75 * np.exp(-tt * 14)
    for at in kicks:
        i = int(at * SR)
        e = min(n, i + len(shape))
        duck[i:e] = np.minimum(duck[i:e], shape[: e - i])
    mix = drums + synths * duck + fx
    t = t_of(TOTAL)
    mix *= np.minimum(1, t / 0.4) * np.minimum(1, (TOTAL - t) / 1.2)
    # Glue and loudness: gentle saturation, then normalise.
    mix = np.tanh(1.6 * mix / np.max(np.abs(mix)) * 1.4)
    return mix


# --- Interface sounds ------------------------------------------------------------------------------

def tick():  # a word landing: short and glassy
    t = t_of(0.06)
    return (np.sin(2 * np.pi * 2600 * t) * 0.6 + np.sin(2 * np.pi * 3900 * t) * 0.3) * np.exp(-t * 100)


def key():  # one keystroke: a crisp mechanical click
    t = t_of(0.04)
    return band(noise(0.04), 2000, 9000) * np.exp(-t * 160) + np.sin(2 * np.pi * 180 * t) * np.exp(-t * 90) * 0.4


def whoosh():  # air past the camera, with pitch movement
    t = t_of(0.6)
    n = noise(0.6)
    out = np.zeros_like(n)
    for i in range(0, len(n), 2400):
        cut = 500 + 5000 * np.sin(np.pi * i / len(n))
        out[i:i + 2400] = band(n[i:i + 2400], 150, cut)
    return out * np.sin(np.pi * t / 0.6) ** 2


def tap():  # the notch opening, Touch ID: a deep, satisfying press
    t = t_of(0.3)
    body = np.sin(2 * np.pi * np.cumsum(70 + 110 * np.exp(-t * 35)) / SR) * np.exp(-t * 14)
    click = band(noise(0.3), 2000, 8000) * np.exp(-t * 300) * 0.5
    return body + click


def chime():  # done / approved: two bright notes
    a, b = bell(81, 1.4), bell(88, 1.2)
    out = a.copy()
    off = int(0.08 * SR)
    out[off:off + len(b)] += b[: len(out) - off]
    return out


def pop():  # a card or row appearing: round and bubbly
    t = t_of(0.12)
    f = 380 + 700 * (1 - np.exp(-t * 60))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 38) * np.minimum(1, t / 0.002)


def swoosh():  # words or a scene arriving: short, airy
    t = t_of(0.28)
    n = noise(0.28)
    out = np.zeros_like(n)
    for i in range(0, len(n), 1200):
        out[i:i + 1200] = band(n[i:i + 1200], 800, 2000 + 9000 * (i / len(n)))
    return out * np.sin(np.pi * t / 0.28) ** 1.5


def rise():  # a ring or bars filling: a quick tonal lift
    t = t_of(0.55)
    f = 300 * 2 ** (2 * t / 0.55)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * np.sin(2 * np.pi * np.cumsum(2 * f) / SR)
    return tone * np.sin(np.pi * t / 0.55) * 0.8


def roll():  # a number counting up: ticks that slow down as it settles
    out = np.zeros(int(1.1 * SR))
    at, gap = 0.0, 0.025
    while at < 1.0:
        add(out, at, tick(), 0.5 + 0.5 * at)
        at += gap
        gap *= 1.09
    return out


def drop():  # a dragged item landing
    t = t_of(0.25)
    return np.sin(2 * np.pi * np.cumsum(220 * np.exp(-t * 8) + 90) / SR) * np.exp(-t * 20) + band(noise(0.25), 1500, 6000) * np.exp(-t * 120) * 0.3


def sparkle():  # milestones and "done": a shimmering run of bells
    out = np.zeros(int(1.6 * SR))
    for k, m in enumerate([86, 90, 93, 98, 102]):
        add(out, k * 0.05, bell(m, 1.2), 0.6 - k * 0.08)
    return out


def clunk():  # the privacy lock closing
    t = t_of(0.35)
    body = np.sin(2 * np.pi * np.cumsum(140 * np.exp(-t * 12) + 60) / SR) * np.exp(-t * 16)
    latch = band(noise(0.35), 2500, 9000) * (np.exp(-t * 200) + np.where(t > 0.06, np.exp(-(t - 0.06) * 260), 0))
    return body + 0.6 * latch


def write(name, mono, gain=0.9):
    data = (mono / (np.max(np.abs(mono)) or 1) * gain * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(np.repeat(data[:, None], 2, axis=1).tobytes())


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    write('music.wav', music(), 0.95)
    write('tick.wav', tick(), 0.5)
    write('key.wav', key(), 0.45)
    write('whoosh.wav', whoosh(), 0.7)
    write('tap.wav', tap(), 0.9)
    write('chime.wav', chime(), 0.6)
    write('pop.wav', pop(), 0.6)
    write('swoosh.wav', swoosh(), 0.55)
    write('rise.wav', rise(), 0.45)
    write('roll.wav', roll(), 0.45)
    write('drop.wav', drop(), 0.8)
    write('sparkle.wav', sparkle(), 0.5)
    write('clunk.wav', clunk(), 0.9)
    print('ok')
