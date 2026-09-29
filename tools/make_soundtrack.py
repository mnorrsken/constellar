#!/usr/bin/env python3
"""Renders the soundtrack: a piece of about five minutes from every music
theme in make_audio.py, with a fade-in and an outro, in
stereo, as MP3 (plain Python, plus the `lame` encoder).

    python3 tools/make_soundtrack.py [--only THEME ...] [--minutes 5] [--wav]
    (or: make soundtrack)

Each piece is a chain of loops as long as the game's, each with all the
theme's layers and a new melody (and every other one with the chords
started elsewhere), so it moves like the game's music but never repeats.
About two thirds in, one calm loop drops the beat; the last loop eases down
as the outro. Each loop's reverb tail runs into the next. Layers are panned
across the stereo field, with a slightly different reverb on each side. The
game's loops are untouched; these are for listening.

Output: build/soundtrack/NN_theme.mp3 (22.05 kHz rendered, encoded at
44.1 kHz VBR with title tags), or .wav with --wav. Everything is seeded, so
a run always makes the same music.
"""
import math
import os
import shutil
import struct
import subprocess
import sys
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_audio as ma  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT_DIR = os.path.normpath(os.path.join(ROOT, "build", "soundtrack"))
SR = ma.SR
ALBUM = "Constellar: Merchant Empire (Soundtrack)"

## Track order and titles.
TRACKS = [
    ("space", "The Open Map"),
    ("core", "Core Worlds"),
    ("agricultural", "Harvest"),
    ("mining", "Down the Shafts"),
    ("refinery", "Gas Giant Winds"),
    ("water", "Ice Fields"),
    ("industrial", "The Foundries"),
    ("frontier", "The Rim"),
    ("research", "Laboratories"),
    ("military", "Garrison"),
    ("robot", "Machine Worlds"),
    ("free_port", "Free Port Bazaar"),
]

BEAT = {"drums", "hits", "scatter"}
## Stereo position (-1 left .. 1 right) by layer kind; the rest alternate.
CENTRE = {"bass", "drone", "drums", "noise"}
SPREAD = [-0.45, 0.4, -0.25, 0.3, -0.35, 0.2]

FADE_IN = 4.0
FADE_OUT = 12.0


def plan(spec, units):
    """The piece as game-length loops: (layer indices, chord rotation, seed
    salt, name) each. Every loop has all the layers and a new melody, except
    one calm loop without the beat about two thirds in; the last one eases
    down as the outro."""
    kinds = [layer[0] for layer in spec["layers"]]
    every = list(range(len(kinds)))
    calm = [i for i, k in enumerate(kinds) if k not in BEAT] or every
    rest = round(units * 0.65) if units >= 4 else -1
    out = []
    for u in range(units):
        name = "outro" if u == units - 1 else "calm" if u == rest else "loop"
        out.append((calm if name == "calm" else every, 2 * (u % 2), u + 1, name))
    return out


def pans(spec):
    out = []
    k = 0
    for layer in spec["layers"]:
        if layer[0] in CENTRE:
            out.append(0.0)
        else:
            out.append(SPREAD[k % len(SPREAD)])
            k += 1
    return out


def render_section(theme, spec, layers, rotation, salt):
    """One loop in stereo, as long as the game's: ([left], [right], length
    in seconds)."""
    sec = dict(spec)
    prog = spec["prog"]
    sec["prog"] = prog[rotation % len(prog):] + prog[:rotation % len(prog)]
    song = ma.Song(sec, seed=ma.hash_name(theme) + salt * 7919)
    n = int((song.length + ma.TAIL) * SR)
    left = [0.0] * n
    right = [0.0] * n
    pan = pans(spec)
    for k in layers:
        layer, cutoff, args = spec["layers"][k]
        buf = [0.0] * n
        ma.LAYERS[layer](song, buf, **args)
        if cutoff:
            ma.lowpass(buf, SR, cutoff)
        angle = (pan[k] + 1.0) * math.pi / 4.0
        gl, gr = math.cos(angle), math.sin(angle)
        left = [a + b * gl for a, b in zip(left, buf)]
        right = [a + b * gr for a, b in zip(right, buf)]
    return left, right, song.length


def render_track(theme, minutes):
    spec = ma.THEMES[theme]
    # Loops as long as the game's, as many as fill the piece.
    unit = ma.Song(spec, seed=1).length
    units = max(2, round(minutes * 60.0 / unit))
    starts = []
    parts = []
    t = 0.0
    for layers, rotation, salt, name in plan(spec, units):
        left, right, length = render_section(theme, spec, layers, rotation, salt)
        if name == "outro":
            # Ease down through the outro, into the final fade.
            m = int(length * SR)
            for i in range(len(left)):
                g = 1.0 - 0.5 * min(1.0, i / m)
                left[i] *= g
                right[i] *= g
        starts.append(t)
        parts.append((left, right))
        t += length
    n = int((t + ma.TAIL) * SR)
    mix_l = [0.0] * n
    mix_r = [0.0] * n
    for start, (left, right) in zip(starts, parts):
        i0 = int(start * SR)
        for i in range(min(len(left), n - i0)):
            mix_l[i0 + i] += left[i]
            mix_r[i0 + i] += right[i]
    wet = spec.get("reverb", 0.3)
    for ch, size in ((mix_l, 1.0), (mix_r, 1.08)):
        ma.lowpass(ch, SR, 5000.0)
        ma.reverb(ch, SR, wet=wet, size=size)
        ma.dc_block(ch, SR)
    # Fade in, and fade the outro's last seconds (and its ring) to silence.
    fade_in = int(FADE_IN * SR)
    fade_out = int(FADE_OUT * SR)
    for i in range(fade_in):
        g = (i / fade_in) ** 2
        mix_l[i] *= g
        mix_r[i] *= g
    for i in range(fade_out):
        g = 0.5 + 0.5 * math.cos(math.pi * i / fade_out)
        j = n - fade_out + i
        mix_l[j] *= g
        mix_r[j] *= g
    # The same loudness as the game's loops, then soft-limit the peaks.
    rms = math.sqrt((sum(x * x for x in mix_l) + sum(x * x for x in mix_r)) / (2 * n)) or 1.0
    g = 0.11 / rms
    mix_l = [math.tanh(x * g * 1.2) / 1.2 for x in mix_l]
    mix_r = [math.tanh(x * g * 1.2) / 1.2 for x in mix_r]
    return mix_l, mix_r


def write_stereo_wav(path, left, right, sr):
    frames = b"".join(struct.pack("<hh", max(-32767, min(32767, int(a * 32767))),
                                  max(-32767, min(32767, int(b * 32767)))) for a, b in zip(left, right))
    header = b"fmt " + struct.pack("<IHHIIHH", 16, 1, 2, sr, sr * 4, 4, 16)
    data = b"data" + struct.pack("<I", len(frames)) + frames
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(header) + len(data)) + b"WAVE" + header + data)


def make(job):
    number, theme, title, minutes, keep_wav = job
    left, right = render_track(theme, minutes)
    base = os.path.join(OUT_DIR, "%02d_%s" % (number, theme))
    write_stereo_wav(base + ".wav", left, right, SR)
    seconds = len(left) / SR
    if keep_wav:
        return "%s.wav  %d:%02d  %s" % (base, seconds // 60, seconds % 60, title)
    subprocess.run(["lame", "--quiet", "-V", "2", "--resample", "44.1",
                    "--tt", title, "--ta", "Constellar", "--tl", ALBUM,
                    "--tn", "%d/%d" % (number, len(TRACKS)), "--tg", "Soundtrack",
                    base + ".wav", base + ".mp3"], check=True)
    os.remove(base + ".wav")
    return "%s.mp3  %d:%02d  %s" % (base, seconds // 60, seconds % 60, title)


def main():
    args = sys.argv[1:]
    keep_wav = "--wav" in args
    minutes = float(args[args.index("--minutes") + 1]) if "--minutes" in args else 5.0
    only = set()
    if "--only" in args:
        for a in args[args.index("--only") + 1:]:
            if a.startswith("--"):
                break
            only.add(a)
    if not keep_wav and shutil.which("lame") is None:
        sys.exit("lame not found: install it (brew install lame), or use --wav")
    os.makedirs(OUT_DIR, exist_ok=True)
    jobs = [(k + 1, theme, title, minutes, keep_wav) for k, (theme, title) in enumerate(TRACKS)
            if not only or theme in only]
    with Pool() as pool:
        for line in pool.imap(make, jobs):
            print(line)


if __name__ == "__main__":
    main()
