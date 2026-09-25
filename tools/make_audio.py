#!/usr/bin/env python3
"""Generates the game's music loops and UI sounds (plain Python, no libraries).

    python3 tools/make_audio.py [--only NAME ...]      (or: make audio)

Music: one seamless loop per world type (the file name is the archetype id
in data/archetypes.json) plus "space" for empty systems and the open map.
Each theme is a mode, a tempo, a chord progression and a set of layers
(pads, bowed strings, drones, plucked strings, bells, drums, a melody, and
sounds of the place: struck metal and steam, wind, drills, water drops,
birds), mixed through a small reverb. The tail that rings past the loop end is folded back onto the
start, and the WAV carries a loop point, so Godot loops it without a seam.

UI: short synthesized blips and chimes (a little starship-console, not too
much). Everything is seeded, so a run always makes the same files.

Output: assets/audio/music/*.wav (22.05 kHz mono) and assets/audio/ui/*.wav
(44.1 kHz mono), 16-bit.
"""
import math
import os
import random
import struct
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MUSIC_DIR = os.path.join(ROOT, "assets", "audio", "music")
UI_DIR = os.path.join(ROOT, "assets", "audio", "ui")

SR = 22050          # music sample rate
UI_SR = 44100       # UI sound sample rate
TABLE = 2048        # wavetable length (power of two)
MASK = TABLE - 1
TAIL = 6.0          # seconds rendered past the loop end, folded back
LOOP_SECONDS = 36.0  # aim for loops about this long

SCALES = {
    "ionian": [0, 2, 4, 5, 7, 9, 11],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "lydian": [0, 2, 4, 6, 7, 9, 11],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
    "aeolian": [0, 2, 3, 5, 7, 8, 10],
    "locrian": [0, 1, 3, 5, 6, 8, 10],
    "hijaz": [0, 1, 4, 5, 7, 8, 10],
    "whole": [0, 2, 4, 6, 8, 10],
}


# --- building blocks ----------------------------------------------------------------

def wavetable(harmonics):
    """One cycle from (harmonic, amplitude) pairs, peak 1."""
    t = [0.0] * TABLE
    for n, a in harmonics:
        w = 2.0 * math.pi * n / TABLE
        for i in range(TABLE):
            t[i] += a * math.sin(w * i)
    peak = max(abs(x) for x in t) or 1.0
    return [x / peak for x in t]


TABLES = {
    "sine": wavetable([(1, 1.0)]),
    "soft_saw": wavetable([(n, 1.0 / n) for n in range(1, 9)]),
    "bright_saw": wavetable([(n, 1.0 / n) for n in range(1, 17)]),
    "square": wavetable([(n, 1.0 / n) for n in range(1, 14, 2)]),
    "organ": wavetable([(1, 1.0), (2, 0.5), (3, 0.3), (4, 0.25), (6, 0.12), (8, 0.08)]),
    # An "ah" vowel: stronger harmonics where a voice's formants sit.
    "choir": wavetable([(1, 1.0), (2, 0.6), (3, 0.8), (4, 1.0), (5, 0.7), (6, 0.4), (7, 0.3),
                        (8, 0.2), (9, 0.25), (10, 0.15), (11, 0.1), (12, 0.08)]),
    "glass": wavetable([(1, 1.0), (3, 0.35), (5, 0.12), (7, 0.05)]),
    # Bowed strings, played softly: harmonics falling a bit faster than a
    # saw's, the body's resonances a little stronger (ten harmonics, so a
    # violin's high notes stay under Nyquist).
    "strings": wavetable([(n, (1.4 if n in (3, 4, 5) else 1.0) / n ** 1.3) for n in range(1, 11)]),
}


def midi_hz(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def tone(buf, sr, start, dur, freq, table, amp, attack=0.01, decay=0.1, sustain=0.8,
         release=0.3, vibrato=0.0, vib_rate=5.0, phase=0.0):
    """A wavetable note with an ADSR envelope, added into buf."""
    tab = TABLES[table]
    i0 = int(start * sr)
    n = int((dur + release) * sr)
    inc = freq * TABLE / sr
    p = phase * TABLE
    end_hold = dur
    two_pi_v = 2.0 * math.pi * vib_rate / sr
    size = len(buf)
    for i in range(n):
        j = i0 + i
        if j >= size:
            break
        t = i / sr
        if t < attack:
            env = t / attack
        elif t < attack + decay:
            env = 1.0 - (1.0 - sustain) * (t - attack) / decay
        elif t < end_hold:
            env = sustain
        else:
            env = sustain * max(0.0, 1.0 - (t - end_hold) / release)
        buf[j] += amp * env * tab[int(p) & MASK]
        if vibrato:
            p += inc * (1.0 + vibrato * math.sin(two_pi_v * i))
        else:
            p += inc


def pluck(buf, sr, start, freq, amp, dur=2.5, damping=0.996, rng=None):
    """Karplus-Strong plucked string."""
    rng = rng or random.Random(1)
    period = max(2, int(sr / freq))
    ring = [rng.uniform(-1.0, 1.0) for _ in range(period)]
    # Soften the attack: each pass takes off more of the bright pick noise.
    for _ in range(4):
        ring = [(ring[k] + ring[k - 1]) * 0.5 for k in range(period)]
    i0 = int(start * sr)
    n = int(dur * sr)
    idx = 0
    size = len(buf)
    for i in range(n):
        j = i0 + i
        if j >= size:
            break
        v = ring[idx]
        nxt = ring[idx + 1 if idx + 1 < period else 0]
        ring[idx] = damping * 0.5 * (v + nxt)
        buf[j] += amp * v
        idx = idx + 1 if idx + 1 < period else 0


def bell(buf, sr, start, freq, amp, dur=3.0, ratio=3.5, index=2.5, attack=0.0):
    """FM bell: bright at the strike, mellowing as it rings. An `attack` (s)
    fades the strike in, for a mallet rather than a hammer."""
    i0 = int(start * sr)
    n = int(dur * sr)
    ramp = attack * sr
    w = 2.0 * math.pi * freq / sr
    wm = w * ratio
    size = len(buf)
    for i in range(n):
        j = i0 + i
        if j >= size:
            break
        env = math.exp(-3.0 * i / (dur * sr))
        fade = min(1.0, i / ramp) if ramp else 1.0
        buf[j] += amp * fade * env * math.sin(w * i + index * env * math.sin(wm * i))


def kick(buf, sr, start, amp, low=45.0, high=110.0, dur=0.45):
    i0 = int(start * sr)
    n = int(dur * sr)
    ph = 0.0
    size = len(buf)
    for i in range(n):
        j = i0 + i
        if j >= size:
            break
        t = i / sr
        f = low + (high - low) * math.exp(-t * 25.0)
        ph += 2.0 * math.pi * f / sr
        buf[j] += amp * math.exp(-t * 9.0) * math.sin(ph)


def noise_hit(buf, sr, start, amp, dur=0.15, bright=True, rng=None, body=0.0):
    """Noise burst: a hat (bright) or a snare/frame drum (dark, with body)."""
    rng = rng or random.Random(2)
    i0 = int(start * sr)
    n = int(dur * sr)
    prev = 0.0
    lp = 0.0
    size = len(buf)
    for i in range(n):
        j = i0 + i
        if j >= size:
            break
        t = i / sr
        x = rng.uniform(-1.0, 1.0)
        if bright:
            y = x - prev  # crude high-pass
            prev = x
        else:
            lp += 0.25 * (x - lp)
            y = lp * 2.0
        env = math.exp(-t * 5.0 / dur)
        s = y + (body * math.sin(2.0 * math.pi * 180.0 * t) if body else 0.0)
        buf[j] += amp * env * s


def chirp(buf, sr, start, f0, f1, dur, amp):
    """A sine gliding f0 -> f1 that swells and fades (birdsong, water drops)."""
    i0 = int(start * sr)
    n = int(dur * sr)
    ph = 0.0
    size = len(buf)
    for i in range(n):
        j = i0 + i
        if j >= size:
            break
        x = i / n
        ph += 2.0 * math.pi * (f0 + (f1 - f0) * x) / sr
        buf[j] += amp * math.sin(math.pi * x) ** 2 * math.sin(ph)


def lowpass(buf, sr, cutoff):
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / sr)
    y = 0.0
    for i in range(len(buf)):
        y += a * (buf[i] - y)
        buf[i] = y


def reverb(buf, sr, wet=0.3, size=1.0):
    """Schroeder reverb: four damped combs in parallel, two all-passes."""
    scale = sr / 44100.0 * size
    combs = [int(d * scale) for d in (1116, 1188, 1277, 1356)]
    aps = [int(d * scale) for d in (556, 441)]
    n = len(buf)
    out = [0.0] * n
    for d in combs:
        line = [0.0] * d
        idx = 0
        store = 0.0
        for i in range(n):
            y = line[idx]
            store = y * 0.8 + store * 0.2  # damping
            line[idx] = buf[i] + store * 0.84
            out[i] += y
            idx = idx + 1 if idx + 1 < d else 0
    for d in aps:
        line = [0.0] * d
        idx = 0
        for i in range(n):
            b = line[idx]
            x = out[i]
            line[idx] = x + b * 0.5
            out[i] = b - x * 0.5
            idx = idx + 1 if idx + 1 < d else 0
    for i in range(n):
        buf[i] = buf[i] * (1.0 - wet) + out[i] * wet * 0.25


def dc_block(buf, sr, cutoff=20.0):
    """High-pass below `cutoff` Hz: removes any DC offset (plucked strings)."""
    a = math.exp(-2.0 * math.pi * cutoff / sr)
    prev_x = 0.0
    prev_y = 0.0
    for i in range(len(buf)):
        x = buf[i]
        prev_y = x - prev_x + a * prev_y
        prev_x = x
        buf[i] = prev_y


def mix_into(dst, src, gain=1.0):
    for i in range(len(dst)):
        dst[i] += src[i] * gain


# --- music -----------------------------------------------------------------------------

class Song:
    """Timing and harmony shared by a theme's layers."""

    def __init__(self, spec, seed):
        self.spec = spec
        self.rng = random.Random(seed)
        self.beat = 60.0 / spec["tempo"]
        self.bar = self.beat * 4
        prog = spec["prog"]
        bpc = spec.get("bars_per_chord", 2)
        cycle = len(prog) * bpc
        bars = max(cycle, int(round(LOOP_SECONDS / self.bar / cycle)) * cycle)
        self.bars = bars
        self.length = bars * self.bar
        scale = SCALES[spec["scale"]]
        self.root = spec["root"]
        self.scale = scale
        # One chord per bpc bars: (start seconds, [midi notes of a triad]).
        self.chords = []
        for b in range(0, bars, bpc):
            deg = prog[(b // bpc) % len(prog)]
            notes = []
            for k in (0, 2, 4):
                d = deg + k
                notes.append(self.root + scale[d % len(scale)] + 12 * (d // len(scale)))
            self.chords.append((b * self.bar, bpc * self.bar, notes))

    def note(self, degree, octave=0):
        s = self.scale
        return self.root + s[degree % len(s)] + 12 * (degree // len(s) + octave)

    def chord_at(self, t):
        for start, dur, notes in self.chords:
            if start <= t < start + dur:
                return notes
        return self.chords[-1][2]


def near(n, centre):
    """The same pitch class moved to the octave nearest `centre`."""
    while n < centre - 6:
        n += 12
    while n > centre + 6:
        n -= 12
    return n


def layer_pad(song, buf, amp=0.18, table="soft_saw", centre=62, detune=0.004, attack=1.5, release=2.5,
              vibrato=0.0):
    for start, dur, notes in song.chords:
        for n in notes:
            f = midi_hz(near(n, centre))
            # Each voice wobbles at its own rate, like players in a section.
            for k, d in enumerate((-detune, 0.0, detune)):
                tone(buf, SR, start, dur, f * (1.0 + d), table, amp / 3.0, attack=attack, decay=0.5,
                     sustain=0.8, release=release, vibrato=vibrato, vib_rate=4.5 + 0.35 * k,
                     phase=song.rng.random())


def layer_drone(song, buf, amp=0.2, table="organ", fifth=True, octave=-1):
    f = midi_hz(song.root + 12 * octave)
    tone(buf, SR, 0.0, song.length, f, table, amp, attack=3.0, decay=0.1, sustain=1.0, release=TAIL - 1)
    if fifth:
        tone(buf, SR, 0.0, song.length, f * 1.5, table, amp * 0.6, attack=4.0, decay=0.1, sustain=1.0,
             release=TAIL - 1)


def layer_bass(song, buf, amp=0.3, pattern=(0, 2), table="soft_saw", pluck_like=True, octave=-1):
    """Chord roots on the given beats of every bar."""
    for bar in range(song.bars):
        for beat in pattern:
            t = bar * song.bar + beat * song.beat
            root = song.chord_at(t)[0]
            f = midi_hz(near(root, 40) + 12 * (octave + 1))
            if pluck_like:
                tone(buf, SR, t, song.beat * 0.6, f, table, amp, attack=0.005, decay=0.25, sustain=0.35,
                     release=0.2)
            else:
                tone(buf, SR, t, song.beat * 1.8, f, table, amp, attack=0.05, decay=0.3, sustain=0.7,
                     release=0.4)


def layer_arp(song, buf, amp=0.2, step=0.5, kind="pluck", centre=67, shape="updown", table="glass"):
    """Chord tones in a steady stream (step in beats)."""
    t = 0.0
    k = 0
    while t < song.length - 1e-6:
        notes = sorted(near(n, centre) for n in song.chord_at(t))
        ring = notes + [notes[0] + 12]
        if shape == "updown":
            seq = ring + ring[-2:0:-1]
        elif shape == "random":
            seq = [song.rng.choice(ring)]
        else:
            seq = ring
        n = seq[k % len(seq)]
        f = midi_hz(n)
        if kind == "pluck":
            pluck(buf, SR, t, f, amp, dur=1.6, rng=song.rng)
        elif kind == "pizz":
            pluck(buf, SR, t, f, amp, dur=0.7, damping=0.985, rng=song.rng)
        elif kind == "bell":
            bell(buf, SR, t, f, amp, dur=1.8, ratio=3.5, index=1.0, attack=0.02)
        elif kind == "marimba":
            bell(buf, SR, t, f, amp, dur=0.6, ratio=4.0, index=0.5, attack=0.008)
        else:
            tone(buf, SR, t, song.beat * step * 0.7, f, table, amp, attack=0.02, decay=0.08,
                 sustain=0.3, release=0.12)
        t += step * song.beat
        k += 1


def layer_bells(song, buf, amp=0.15, every=2.0, chance=1.0, octave=1, ratio=3.5, dur=4.0, index=1.2):
    """A bell on chord tones every few beats (some skipped)."""
    t = 0.0
    while t < song.length - 1e-6:
        if song.rng.random() < chance:
            n = song.rng.choice(song.chord_at(t)) + 12 * octave
            bell(buf, SR, t, midi_hz(near(n, 72 + 12 * (octave - 1))), amp, dur=dur, ratio=ratio, index=index,
                 attack=0.03)
        t += every * song.beat


def layer_melody(song, buf, amp=0.18, kind="pluck", rhythm=(1, 1, 0.5, 0.5, 1), centre=69, rest=0.2,
                 table="glass", second_half_only=True, attack=0.03, vibrato=0.004):
    """A seeded melody: a four-bar phrase, played again with its end changed."""
    phrase = []
    t = 0.0
    deg = 7
    while t < 4 * song.bar - 1e-6:
        for d in rhythm:
            if t >= 4 * song.bar - 1e-6:
                break
            deg = max(3, min(13, deg + song.rng.choice((-2, -1, -1, 1, 1, 2))))
            phrase.append((t, d, None if song.rng.random() < rest else deg))
            t += d * song.beat
    start_bar = song.bars // 2 if second_half_only and song.bars >= 8 else 0
    for rep_bar in range(start_bar, song.bars, 4):
        base = rep_bar * song.bar
        for t, d, deg in phrase:
            if deg is None or base + t >= song.length:
                continue
            chord = song.chord_at(base + t)
            n = song.note(deg)
            # On the beat, lean onto a chord tone.
            if abs(t / song.beat - round(t / song.beat)) < 1e-6:
                n = min(chord, key=lambda c: abs(near(c, n) - n))
            f = midi_hz(near(n, centre))
            if kind == "pluck":
                pluck(buf, SR, base + t, f, amp, dur=2.0, rng=song.rng)
            elif kind == "bell":
                bell(buf, SR, base + t, f, amp, dur=2.5, ratio=2.0, index=0.8, attack=0.03)
            else:
                tone(buf, SR, base + t, d * song.beat * 0.9, f, table, amp, attack=attack, decay=0.2,
                     sustain=0.7, release=0.3, vibrato=vibrato, vib_rate=5.5)


def layer_drums(song, buf, kicks=(0, 2), snares=(), hats=(), amp=0.5, snare_amp=0.25, hat_amp=0.06,
                fill_every=0, toms=False):
    """Beats (in beats of the bar) for kick, snare/frame drum and hats."""
    for bar in range(song.bars):
        b0 = bar * song.bar
        for k in kicks:
            if toms:
                kick(buf, SR, b0 + k * song.beat, amp, low=70.0, high=140.0, dur=0.6)
            else:
                kick(buf, SR, b0 + k * song.beat, amp)
        for s in snares:
            noise_hit(buf, SR, b0 + s * song.beat, snare_amp, dur=0.18, bright=False, rng=song.rng, body=0.4)
        for h in hats:
            noise_hit(buf, SR, b0 + h * song.beat, hat_amp, dur=0.05, bright=True, rng=song.rng)
        if fill_every and bar % fill_every == fill_every - 1:
            for q in range(4):
                noise_hit(buf, SR, b0 + (3 + q * 0.25) * song.beat, snare_amp * (0.5 + q * 0.15), dur=0.12,
                          bright=False, rng=song.rng, body=0.3)


def layer_scatter(song, buf, amp=0.2, count=10):
    """Irregular noise hits and low thumps (anarchy)."""
    for _ in range(count):
        t = song.rng.uniform(0.0, song.length)
        if song.rng.random() < 0.5:
            noise_hit(buf, SR, t, amp, dur=0.3, bright=False, rng=song.rng, body=0.2)
        else:
            kick(buf, SR, t, amp * 1.5, low=38.0, high=80.0, dur=0.7)


def layer_hits(song, buf, pattern=(), every=1, amp=0.1, kind="clang", octave=1, ratio=1.41, index=3.0,
               dur=0.5):
    """Hits on beats of every `every`-th bar: struck metal on the chord root
    (an inharmonic FM ratio), or a burst of steam."""
    for bar in range(0, song.bars, every):
        for b in pattern:
            t = bar * song.bar + b * song.beat
            if kind == "hiss":
                noise_hit(buf, SR, t, amp, dur=dur, bright=True, rng=song.rng)
            else:
                f = midi_hz(near(song.chord_at(t)[0], 60 + 12 * octave))
                bell(buf, SR, t, f, amp, dur=dur, ratio=ratio, index=index, attack=0.006)


def layer_noise(song, buf, amp=0.1, lo=200.0, hi=1200.0, bars=4):
    """A bed of filtered noise (wind, a drill's rumble) whose cutoff swells
    lo -> hi -> lo every `bars` bars; amp is its RMS. It repeats exactly over
    the loop, so it leaves no tail to fold back."""
    n = int(song.length * SR)
    cycles = max(1, round(song.bars / bars))
    noise = [song.rng.uniform(-1.0, 1.0) for _ in range(n)]
    out = [0.0] * n
    y1 = y2 = 0.0
    # Two passes: the first only settles the filter, so the end meets the start.
    for keep in (False, True):
        for i in range(n):
            s = 0.5 - 0.5 * math.cos(2.0 * math.pi * cycles * i / n)
            a = 1.0 - math.exp(-2.0 * math.pi * lo * (hi / lo) ** s / SR)
            y1 += a * (noise[i] - y1)
            y2 += a * (y1 - y2)
            if keep:
                out[i] = (0.4 + 0.6 * s) * y2
    rms = math.sqrt(sum(x * x for x in out) / n) or 1.0
    for i in range(n):
        buf[i] += out[i] * amp / rms


def layer_drops(song, buf, amp=0.1, every=0.5, chance=0.35, centre=81):
    """Water drops: quick rising blips on chord tones, now and then."""
    t = 0.0
    while t < song.length - 1e-6:
        if song.rng.random() < chance:
            f = midi_hz(near(song.rng.choice(song.chord_at(t)), centre))
            chirp(buf, SR, t, f, f * 1.6, 0.07, amp)
        t += every * song.beat


def layer_birds(song, buf, amp=0.03, count=6):
    """Birdsong: a few short phrases of high chirps at random moments."""
    for _ in range(count):
        t = song.rng.uniform(0.0, song.length - 2.0)
        f = song.rng.uniform(2600.0, 4200.0)
        for _ in range(song.rng.randint(2, 5)):
            d = song.rng.uniform(0.05, 0.12)
            f1 = f * song.rng.choice((0.8, 1.15, 1.3))
            chirp(buf, SR, t, f, f1, d, amp)
            t += d + song.rng.uniform(0.03, 0.12)
            f = f1 if 2000.0 < f1 < 5000.0 else f


LAYERS = {
    "pad": layer_pad, "drone": layer_drone, "bass": layer_bass, "arp": layer_arp, "bells": layer_bells,
    "melody": layer_melody, "drums": layer_drums, "scatter": layer_scatter, "hits": layer_hits,
    "noise": layer_noise, "drops": layer_drops, "birds": layer_birds,
}

## Themes: world type (archetype id, or "space") -> the music. Layers are
## (name, cutoff Hz or 0, {arguments}).
THEMES = {
    # The open map and empty systems: slow, wide, no beat.
    "space": {"tempo": 50, "root": 43, "scale": "lydian", "prog": [0, 1, 0, 4], "reverb": 0.55, "layers": [
        ("pad", 1600, {"amp": 0.2, "table": "soft_saw", "centre": 58, "attack": 3.0, "release": 4.0}),
        ("drone", 900, {"amp": 0.16, "table": "sine"}),
        ("bells", 3500, {"amp": 0.07, "every": 3, "chance": 0.45, "octave": 1, "dur": 5.0}),
    ]},
    # Old capital worlds: stately and bright (Lydian), bells over an organ.
    "core": {"tempo": 72, "root": 50, "scale": "lydian", "prog": [0, 4, 1, 0], "reverb": 0.45, "layers": [
        ("pad", 2200, {"amp": 0.18, "table": "organ", "centre": 62}),
        ("bass", 700, {"amp": 0.26, "pattern": (0,), "pluck_like": False, "table": "sine"}),
        ("arp", 3500, {"amp": 0.1, "step": 1.0, "kind": "bell", "centre": 74}),
        ("melody", 3000, {"amp": 0.11, "kind": "tone", "table": "glass", "rhythm": (2, 1, 1), "centre": 74}),
    ]},
    # Farms: soft violins and a cello (Ionian), pizzicato, a violin tune, birds.
    "agricultural": {"tempo": 72, "root": 50, "scale": "ionian", "prog": [0, 3, 5, 4], "reverb": 0.45,
                     "layers": [
        ("pad", 1800, {"amp": 0.2, "table": "strings", "centre": 62, "attack": 2.5, "release": 3.0,
                       "detune": 0.003, "vibrato": 0.004}),
        ("bass", 900, {"amp": 0.13, "pattern": (0, 2), "pluck_like": False, "table": "strings"}),
        ("arp", 3500, {"amp": 0.2, "step": 1.0, "kind": "pizz", "centre": 67, "shape": "up"}),
        ("melody", 2600, {"amp": 0.16, "kind": "tone", "table": "strings", "rhythm": (2, 1, 1, 3, 1),
                          "centre": 74, "rest": 0.1, "attack": 0.25, "vibrato": 0.006}),
        ("birds", 0, {"amp": 0.06, "count": 7}),
    ]},
    # Down the shafts: a low drone and hummed choir (Aeolian), drill rumble,
    # heavy toms, picks ringing on rock, the odd rockfall.
    "mining": {"tempo": 66, "root": 38, "scale": "aeolian", "prog": [0, 5, 0, 6], "reverb": 0.5, "layers": [
        ("drone", 500, {"amp": 0.2, "table": "soft_saw"}),
        ("pad", 1000, {"amp": 0.12, "table": "choir", "centre": 53, "attack": 2.0}),
        ("noise", 0, {"amp": 0.05, "lo": 50.0, "hi": 260.0, "bars": 4}),
        ("drums", 0, {"kicks": (0, 2.5), "amp": 0.45, "toms": True}),
        ("hits", 2500, {"pattern": (1.0, 1.5), "every": 2, "amp": 0.09, "octave": 2, "ratio": 2.76, "index": 2.0,
                     "dur": 0.35}),
        ("scatter", 1200, {"amp": 0.25, "count": 6}),
    ]},
    # Skimming a gas giant: howling wind, an airy choir (Mixolydian), a slow
    # double-thump of pumps, a far bell.
    "refinery": {"tempo": 60, "root": 45, "scale": "mixolydian", "prog": [0, 6, 3, 0], "reverb": 0.5,
                 "layers": [
        ("noise", 0, {"amp": 0.045, "lo": 300.0, "hi": 2400.0, "bars": 4}),
        ("pad", 1800, {"amp": 0.16, "table": "choir", "centre": 60, "attack": 3.0, "vibrato": 0.002}),
        ("drone", 700, {"amp": 0.14, "table": "sine"}),
        ("drums", 0, {"kicks": (0, 0.5), "amp": 0.25}),
        ("bells", 3500, {"amp": 0.06, "every": 4, "chance": 0.6, "octave": 1, "ratio": 2.0, "dur": 4.0}),
    ]},
    # Ice fields: cold glass (Dorian), dripping water, a thin wind, high bells.
    "water": {"tempo": 80, "root": 50, "scale": "dorian", "prog": [0, 3, 0, 4], "reverb": 0.55, "layers": [
        ("pad", 2600, {"amp": 0.15, "table": "glass", "centre": 64, "attack": 2.0}),
        ("bass", 700, {"amp": 0.2, "pattern": (0,), "pluck_like": False, "table": "sine"}),
        ("drops", 3500, {"amp": 0.15, "every": 0.5, "chance": 0.35, "centre": 81}),
        ("noise", 0, {"amp": 0.02, "lo": 400.0, "hi": 1500.0, "bars": 8}),
        ("bells", 3500, {"amp": 0.07, "every": 3, "chance": 0.6, "octave": 2, "ratio": 2.0, "dur": 3.0}),
    ]},
    # Factories: a pounding four-to-the-floor, a grinding sequencer bass
    # (Phrygian), anvils ringing, a steam valve every other bar.
    "industrial": {"tempo": 100, "root": 40, "scale": "phrygian", "prog": [0, 1, 0, 6], "reverb": 0.3,
                   "layers": [
        ("pad", 1200, {"amp": 0.12, "table": "bright_saw", "centre": 55, "attack": 1.0, "detune": 0.008}),
        ("bass", 600, {"amp": 0.26, "pattern": (0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5), "table": "square"}),
        ("drums", 0, {"kicks": (0, 1, 2, 3), "snares": (1, 3), "hats": (0.5, 1.5, 2.5, 3.5), "amp": 0.34,
                      "snare_amp": 0.2, "hat_amp": 0.04}),
        ("hits", 2500, {"pattern": (0.75, 2.25, 3.5), "amp": 0.1, "octave": 1, "ratio": 1.41, "index": 3.0,
                     "dur": 0.7}),
        ("hits", 3500, {"kind": "hiss", "pattern": (3.0,), "every": 2, "amp": 0.12, "dur": 0.9}),
    ]},
    # The rim: a strummed guitar and a harmonica (Mixolydian), a loping beat.
    "frontier": {"tempo": 100, "root": 43, "scale": "mixolydian", "prog": [0, 6, 3, 0], "reverb": 0.3,
                 "layers": [
        ("arp", 3500, {"amp": 0.14, "step": 0.5, "kind": "pluck", "centre": 60, "shape": "up"}),
        ("bass", 800, {"amp": 0.24, "pattern": (0, 2), "table": "soft_saw"}),
        ("drums", 0, {"kicks": (0, 2), "snares": (1, 3), "amp": 0.22, "snare_amp": 0.1, "toms": True}),
        ("melody", 2000, {"amp": 0.09, "kind": "tone", "table": "square", "rhythm": (1, 0.5, 0.5, 2),
                          "centre": 69, "attack": 0.05, "vibrato": 0.008}),
    ]},
    # Laboratories: curious and sparkling (Lydian), glass blips, bell tunes.
    "research": {"tempo": 84, "root": 52, "scale": "lydian", "prog": [0, 1, 0, 5], "reverb": 0.45, "layers": [
        ("pad", 2000, {"amp": 0.14, "table": "sine", "centre": 64, "attack": 2.5}),
        ("arp", 3200, {"amp": 0.09, "step": 0.5, "kind": "tone", "table": "glass", "centre": 76,
                       "shape": "random"}),
        ("bells", 3500, {"amp": 0.07, "every": 2, "chance": 0.4, "octave": 2, "ratio": 3.5, "dur": 2.5}),
        ("melody", 3500, {"amp": 0.09, "kind": "bell", "rhythm": (1.5, 0.5, 2), "centre": 72}),
    ]},
    # Garrisons: a marching drum, a low ostinato, brass-like chords (Aeolian).
    "military": {"tempo": 96, "root": 45, "scale": "aeolian", "prog": [0, 5, 6, 4], "reverb": 0.3, "layers": [
        ("pad", 1400, {"amp": 0.15, "table": "bright_saw", "centre": 57, "attack": 0.4}),
        ("bass", 700, {"amp": 0.28, "pattern": (0, 0.5, 1.5, 2, 2.5, 3.5), "table": "soft_saw"}),
        ("drums", 0, {"kicks": (0, 1, 2, 3), "snares": (1, 3), "amp": 0.3, "snare_amp": 0.2, "fill_every": 4}),
    ]},
    # Machines: glassy sixteenths on a whole-tone scale, a ticking clock.
    "robot": {"tempo": 112, "root": 57, "scale": "whole", "prog": [0, 1, 0, 5], "reverb": 0.4, "layers": [
        ("pad", 1800, {"amp": 0.12, "table": "sine", "centre": 64, "attack": 2.0}),
        ("arp", 2600, {"amp": 0.1, "step": 0.25, "kind": "tone", "table": "glass", "centre": 76,
                       "shape": "random"}),
        ("drums", 0, {"kicks": (), "hats": (0, 0.75, 1.5, 2, 2.75, 3.5), "hat_amp": 0.05}),
        ("bells", 3500, {"amp": 0.06, "every": 2, "chance": 0.5, "octave": 1, "ratio": 2.0, "dur": 2.0}),
    ]},
    # A bazaar: marimba and an oud-like lute (Hijaz), hand drums.
    "free_port": {"tempo": 108, "root": 50, "scale": "hijaz", "prog": [0, 6, 1, 0], "reverb": 0.3, "layers": [
        ("arp", 3500, {"amp": 0.11, "step": 0.5, "kind": "marimba", "centre": 67}),
        ("bass", 700, {"amp": 0.24, "pattern": (0, 1.5, 2, 3), "table": "soft_saw"}),
        ("drums", 0, {"kicks": (0, 1.5, 2.5), "snares": (3,), "hats": (0.5, 1, 2, 3, 3.5), "amp": 0.3,
                      "snare_amp": 0.14, "hat_amp": 0.04, "toms": True}),
        ("melody", 3500, {"amp": 0.22, "kind": "pluck", "rhythm": (0.5, 0.5, 1, 0.5, 0.5, 1), "centre": 69,
                       "second_half_only": False, "rest": 0.15}),
    ]},
}


def render_theme(name, spec):
    song = Song(spec, seed=hash_name(name))
    n = int((song.length + TAIL) * SR)
    mix = [0.0] * n
    for layer, cutoff, args in spec["layers"]:
        buf = [0.0] * n
        LAYERS[layer](song, buf, **args)
        if cutoff:
            lowpass(buf, SR, cutoff)
        mix_into(mix, buf)
    # Round off the top end of everything: softer hats, strikes and edges.
    lowpass(mix, SR, 5000.0)
    reverb(mix, SR, wet=spec.get("reverb", 0.3))
    dc_block(mix, SR)
    # Fold what rings past the end back onto the start: a seamless loop.
    loop = int(song.length * SR)
    for i in range(n - loop):
        mix[i] += mix[loop + i]
    mix = mix[:loop]
    # Same loudness for every theme, then soft-limit the peaks.
    rms = math.sqrt(sum(x * x for x in mix) / len(mix)) or 1.0
    g = 0.11 / rms
    out = [math.tanh(x * g * 1.2) / 1.2 for x in mix]
    return out, song


def hash_name(name):
    h = 0
    for ch in name:
        h = (h * 131 + ord(ch)) % 2147483647
    return h


# --- UI sounds ---------------------------------------------------------------------------

def ui_blip(buf, start, freq, dur, amp, table="sine", glide=0.0):
    """A short console tone with a quick attack and a soft tail."""
    tab = TABLES[table]
    i0 = int(start * UI_SR)
    n = int(dur * UI_SR)
    p = 0.0
    size = len(buf)
    for i in range(n):
        j = i0 + i
        if j >= size:
            break
        t = i / UI_SR
        env = min(1.0, t / 0.004) * math.exp(-t * 4.0 / dur)
        f = freq * (1.0 + glide * t / dur)
        buf[j] += amp * env * tab[int(p) & MASK]
        p += f * TABLE / UI_SR


def ui_sound(name):
    """name -> samples (44.1 kHz)."""
    rng = random.Random(hash_name(name))
    if name == "click":
        b = [0.0] * int(0.06 * UI_SR)
        ui_blip(b, 0.0, 1850.0, 0.035, 0.5)
        ui_blip(b, 0.0, 2775.0, 0.02, 0.15)
    elif name == "select":
        b = [0.0] * int(0.18 * UI_SR)
        ui_blip(b, 0.0, 1175.0, 0.07, 0.45)
        ui_blip(b, 0.055, 1568.0, 0.1, 0.4)
    elif name == "open":
        b = [0.0] * int(0.3 * UI_SR)
        for k, f in enumerate((784.0, 1047.0, 1319.0)):
            ui_blip(b, k * 0.045, f, 0.12, 0.35, table="glass")
    elif name == "close":
        b = [0.0] * int(0.3 * UI_SR)
        for k, f in enumerate((1319.0, 1047.0, 784.0)):
            ui_blip(b, k * 0.04, f, 0.1, 0.3, table="glass")
    elif name == "confirm":
        b = [0.0] * int(0.6 * UI_SR)
        for k, f in enumerate((1047.0, 1319.0, 1568.0)):
            bell(b, UI_SR, k * 0.03, f, 0.22, dur=0.5, ratio=2.0, index=1.0)
    elif name == "error":
        b = [0.0] * int(0.3 * UI_SR)
        ui_blip(b, 0.0, 330.0, 0.09, 0.4, table="square")
        ui_blip(b, 0.12, 262.0, 0.12, 0.4, table="square")
        lowpass(b, UI_SR, 2500.0)
    elif name == "chime":
        b = [0.0] * int(1.2 * UI_SR)
        bell(b, UI_SR, 0.0, 1047.0, 0.3, dur=1.1, ratio=3.0, index=1.2)
        bell(b, UI_SR, 0.12, 1568.0, 0.18, dur=0.9, ratio=3.0, index=1.0)
    elif name == "coin":
        b = [0.0] * int(0.5 * UI_SR)
        bell(b, UI_SR, 0.0, 1568.0, 0.25, dur=0.3, ratio=4.0, index=0.8)
        bell(b, UI_SR, 0.07, 2093.0, 0.25, dur=0.4, ratio=4.0, index=0.8)
    elif name == "loss":
        b = [0.0] * int(0.4 * UI_SR)
        ui_blip(b, 0.0, 523.0, 0.12, 0.35, table="glass")
        ui_blip(b, 0.1, 392.0, 0.2, 0.35, table="glass")
    elif name == "hail":
        b = [0.0] * int(0.6 * UI_SR)
        for k, f in enumerate((784.0, 988.0, 1175.0)):
            ui_blip(b, k * 0.08, f, 0.16, 0.32, table="glass", glide=0.01)
    elif name == "alert":
        b = [0.0] * int(0.9 * UI_SR)
        for k in range(2):
            ui_blip(b, k * 0.36, 440.0, 0.16, 0.35, table="square", glide=-0.08)
            ui_blip(b, k * 0.36 + 0.17, 370.0, 0.16, 0.35, table="square", glide=-0.08)
        lowpass(b, UI_SR, 1800.0)
    elif name == "pause":
        b = [0.0] * int(0.15 * UI_SR)
        ui_blip(b, 0.0, 880.0, 0.1, 0.35, glide=-0.2)
    elif name == "resume":
        b = [0.0] * int(0.15 * UI_SR)
        ui_blip(b, 0.0, 740.0, 0.1, 0.35, glide=0.25)
    else:
        raise KeyError(name)
    # A touch of room, then normalise to a gentle peak.
    tail = [0.0] * int(0.25 * UI_SR)
    b = b + tail
    reverb(b, UI_SR, wet=0.18, size=0.5)
    peak = max(abs(x) for x in b) or 1.0
    return [x * 0.5 / peak for x in b]


UI_SOUNDS = ["click", "select", "open", "close", "confirm", "error", "chime", "coin", "loss", "hail",
             "alert", "pause", "resume"]


# --- files -----------------------------------------------------------------------------

def write_wav(path, samples, sr, loop=False):
    """16-bit mono WAV; with `loop`, a 'smpl' chunk loops the whole file."""
    data = b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples)
    chunks = b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, sr, sr * 2, 2, 16)
    chunks += b"data" + struct.pack("<I", len(data)) + data
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(samples) - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)


def main():
    only = set(sys.argv[sys.argv.index("--only") + 1:]) if "--only" in sys.argv else None
    os.makedirs(MUSIC_DIR, exist_ok=True)
    os.makedirs(UI_DIR, exist_ok=True)
    for name, spec in THEMES.items():
        if only and name not in only:
            continue
        samples, song = render_theme(name, spec)
        write_wav(os.path.join(MUSIC_DIR, name + ".wav"), samples, SR, loop=True)
        print("music %-12s %2d bars at %3d bpm = %.1f s" % (name, song.bars, spec["tempo"], song.length))
    for name in UI_SOUNDS:
        if only and name not in only:
            continue
        write_wav(os.path.join(UI_DIR, name + ".wav"), ui_sound(name), UI_SR)
        print("ui    %s" % name)


if __name__ == "__main__":
    main()
