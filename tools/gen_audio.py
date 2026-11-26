#!/usr/bin/env python3
"""Gera TODO o áudio do jogo (efeitos, música de menu e ambientes) por síntese — 100% original, sem
direitos autorais. Saída: assets/audio/*.pcm (PCM 16 bits, mono, 22050 Hz, sem cabeçalho).
O jogo lê esses arquivos em tempo de execução (AudioManager) e monta AudioStreamWAV, sem importação.
Requer: python3 + numpy.   Uso: python3 tools/gen_audio.py"""
import os
import numpy as np

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = np.random.default_rng(20260611)


def tt(dur):
    return np.arange(int(dur * RATE)) / RATE


def decay(n, tau):
    return np.exp(-np.arange(n) / (tau * RATE))


def fade(x, a=0.004, r=0.01):
    n = len(x)
    na, nr = max(int(a * RATE), 1), max(int(r * RATE), 1)
    x = x.copy()
    x[:na] *= np.linspace(0, 1, na)
    x[-nr:] *= np.linspace(1, 0, nr)
    return x


def sine(f, dur, ph=0.0):
    return np.sin(2 * np.pi * f * tt(dur) + ph)


def tri(f, dur):
    return 2 / np.pi * np.arcsin(np.sin(2 * np.pi * f * tt(dur)))


def sweep(f0, f1, dur):
    t = tt(dur)
    f = f0 + (f1 - f0) * (t / dur)
    return np.sin(2 * np.pi * np.cumsum(f) / RATE)


def noise(dur):
    return rng.standard_normal(int(dur * RATE))


def lowpass(x, fc):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / RATE)
    return np.fft.irfft(spec / (1 + (f / fc) ** 2), len(x))


def highpass(x, fc):
    return x - lowpass(x, fc)


def pad(x, n):
    return np.pad(x, (0, max(n - len(x), 0)))[:n]


def mix(*parts, n=None):
    n = n or max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out += pad(p, n)
    return out


def at(x, start, total):
    out = np.zeros(int(total * RATE))
    s = int(start * RATE)
    seg = x[: max(len(out) - s, 0)]
    out[s:s + len(seg)] = seg
    return out


def save(name, x, peak=0.8):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = np.clip(x / m * peak, -1, 1)
    pcm = (x * 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".pcm"), "wb") as f:
        f.write(pcm.tobytes())
    print("%-14s %6.2fs %7d bytes" % (name, len(x) / RATE, pcm.nbytes))


def shot(dur, tau, lp, thump_f, thump_tau, crack=0.6, echo=0.0):
    n = int(dur * RATE)
    body = lowpass(noise(dur), lp) * decay(n, tau)
    crack_s = highpass(noise(dur), 3000) * decay(n, tau * 0.25) * crack
    th = sine(thump_f, dur) * decay(n, thump_tau) * 1.4
    x = body + crack_s + th
    if echo > 0:
        x = mix(x, at(x * echo, 0.12, dur), n=n)
    return fade(x, 0.001, 0.02)


# ------------------------------------------------------------------ efeitos
def make_sfx():
    save("ui_click", fade(sine(1400, 0.06) * decay(int(0.06 * RATE), 0.02) + 0.4 * sine(2800, 0.06) * decay(int(0.06 * RATE), 0.01)), 0.5)
    save("ui_back", fade(sweep(620, 300, 0.12) * decay(int(0.12 * RATE), 0.06)), 0.5)
    save("ui_confirm", mix(at(sine(660, 0.09), 0.0, 0.3) * 1.0, at(sine(990, 0.14) * decay(int(0.14 * RATE), 0.07), 0.08, 0.3)), 0.5)
    save("pickup", mix(*[at(fade(tri(f, 0.09) * decay(int(0.09 * RATE), 0.05)), i * 0.065, 0.3) for i, f in enumerate([784, 988, 1319])]), 0.55)
    save("equip", mix(lowpass(noise(0.07), 3000) * decay(int(0.07 * RATE), 0.02), sine(180, 0.1) * decay(int(0.1 * RATE), 0.04)), 0.5)
    save("empty", fade(highpass(noise(0.04), 1500) * decay(int(0.04 * RATE), 0.01) + 0.6 * sine(900, 0.04) * decay(int(0.04 * RATE), 0.01)), 0.5)
    click = lambda: fade(highpass(noise(0.035), 1200) * decay(int(0.035 * RATE), 0.01) + 0.7 * sine(520, 0.035) * decay(int(0.035 * RATE), 0.012))
    swish = lowpass(noise(0.14), 2500) * np.hanning(int(0.14 * RATE)) * 0.6
    save("reload", mix(at(click(), 0.0, 0.65), at(swish, 0.18, 0.65), at(click() * 1.2, 0.46, 0.65)), 0.7)
    save("heal", fade(sweep(440, 880, 0.4) * np.hanning(int(0.4 * RATE)) + 0.3 * sweep(880, 1320, 0.4) * np.hanning(int(0.4 * RATE))), 0.5)
    save("shot_pistol", shot(0.22, 0.045, 4200, 130, 0.07), 0.85)
    save("shot_smg", shot(0.15, 0.03, 5200, 170, 0.05, 0.7), 0.8)
    save("shot_rifle", shot(0.32, 0.075, 3600, 95, 0.09, 0.7, 0.25), 0.9)
    save("shot_shotgun", shot(0.5, 0.12, 2600, 70, 0.14, 0.5, 0.3), 0.95)
    save("shot_dmr", shot(0.65, 0.14, 3000, 60, 0.16, 0.8, 0.35), 0.95)
    save("hit", fade(sweep(900, 600, 0.06) * decay(int(0.06 * RATE), 0.03) + lowpass(noise(0.06), 2500) * decay(int(0.06 * RATE), 0.015) * 0.5), 0.55)
    save("hit_confirm", fade(sine(1500, 0.07) * decay(int(0.07 * RATE), 0.03) + 0.5 * sine(2250, 0.07) * decay(int(0.07 * RATE), 0.02)), 0.6)
    save("hurt", fade(sine(160, 0.16) * decay(int(0.16 * RATE), 0.06) * 1.2 + lowpass(noise(0.16), 800) * decay(int(0.16 * RATE), 0.05)), 0.75)
    save("step_a", fade(lowpass(noise(0.1), 900) * decay(int(0.1 * RATE), 0.03)), 0.6)
    save("step_b", fade(lowpass(noise(0.1), 1300) * decay(int(0.1 * RATE), 0.03)), 0.6)
    save("jump", fade(sweep(260, 520, 0.11) * np.hanning(int(0.11 * RATE)) + 0.3 * lowpass(noise(0.11), 1200) * np.hanning(int(0.11 * RATE))), 0.5)
    save("land", fade(sine(90, 0.16) * decay(int(0.16 * RATE), 0.06) * 1.3 + lowpass(noise(0.16), 600) * decay(int(0.16 * RATE), 0.04)), 0.7)
    beep = lambda f, d: fade(sine(f, d) * (0.7 + 0.3 * sine(8, d)), 0.005, 0.02)
    save("zone_warning", mix(at(beep(880, 0.13), 0.0, 0.55), at(beep(880, 0.13), 0.26, 0.55)), 0.6)
    save("countdown", fade(sine(660, 0.16) * np.hanning(int(0.16 * RATE))), 0.55)
    save("go", fade((sine(990, 0.4) + 0.4 * sine(1980, 0.4)) * decay(int(0.4 * RATE), 0.2)), 0.6)
    notes = [523.25, 659.25, 783.99, 1046.5]
    chord = sum(tri(f, 0.7) for f in notes) * 0.25 * decay(int(0.7 * RATE), 0.35)
    save("win", mix(*[at(fade(tri(f, 0.16) * decay(int(0.16 * RATE), 0.08)), i * 0.14, 1.4) for i, f in enumerate(notes)], at(chord, 0.55, 1.4)), 0.7)
    save("lose", mix(*[at(fade(tri(f, 0.26) * decay(int(0.26 * RATE), 0.12)), i * 0.22, 1.0) for i, f in enumerate([440, 349.2, 293.7])],
                     at(lowpass(noise(0.6), 200) * decay(int(0.6 * RATE), 0.3) * 0.6, 0.3, 1.0)), 0.6)
    save("death", fade(sweep(320, 60, 0.55) * decay(int(0.55 * RATE), 0.25) + lowpass(noise(0.55), 700) * decay(int(0.55 * RATE), 0.2) * 0.5), 0.7)


# ------------------------------------------------------------------ música e ambientes
def make_music():
    bpm = 96
    beat = 60 / bpm
    bar = 4 * beat
    chords = [(220.0, [220.0, 261.63, 329.63]), (174.61, [174.61, 220.0, 261.63]), (261.63, [261.63, 329.63, 392.0]), (196.0, [196.0, 246.94, 293.66])] * 2
    total = bar * len(chords)
    n = int(total * RATE)
    tail = int(3 * RATE)
    buf = np.zeros(n + tail)
    for i, (root, notes) in enumerate(chords):
        s = int(i * bar * RATE)
        d = bar + 1.2
        pad_s = sum(np.sin(2 * np.pi * f * tt(d)) + 0.4 * np.sin(2 * np.pi * 2 * f * tt(d) + 0.3) + 0.15 * np.sin(2 * np.pi * 3 * f * tt(d)) for f in notes)
        env = np.minimum(1, tt(d) / 0.8) * np.exp(-np.maximum(tt(d) - bar, 0) / 0.5)
        buf[s:s + len(pad_s)] += pad_s * env * 0.11
        for b in (0, 2):  # baixo
            bs = s + int(b * beat * RATE)
            bass = sine(root / 2, beat * 1.6) * decay(int(beat * 1.6 * RATE), 0.35) + 0.3 * sine(root, beat * 1.6) * decay(int(beat * 1.6 * RATE), 0.2)
            buf[bs:bs + len(bass)] += bass * 0.45
        for k in range(8):  # arpejo
            f = notes[k % 3] * (2 if k % 4 < 2 else 1) * 2
            a = tri(f, 0.4) * decay(int(0.4 * RATE), 0.12)
            ss = s + int(k * beat / 2 * RATE)
            buf[ss:ss + len(a)] += fade(a, 0.003, 0.05) * 0.10
        for b in range(4):  # bumbo suave + chimbal
            ks = s + int(b * beat * RATE)
            kick = np.sin(2 * np.pi * np.cumsum(np.linspace(110, 45, int(0.18 * RATE))) / RATE) * decay(int(0.18 * RATE), 0.07)
            buf[ks:ks + len(kick)] += kick * 0.35
            hs = s + int((b + 0.5) * beat * RATE)
            hat = highpass(noise(0.05), 6000) * decay(int(0.05 * RATE), 0.012)
            buf[hs:hs + len(hat)] += hat * 0.05
    loop = buf[:n].copy()
    loop[:tail] += buf[n:n + tail]
    save("music_menu", loop, 0.55)


def make_ambient():
    d = 12.0
    n = int(d * RATE)
    t = tt(d)
    # cidade: rumor grave + zumbido + passagens distantes
    rumble = lowpass(noise(d), 380) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.11 * t))
    hum = 0.08 * np.sin(2 * np.pi * 55 * t) + 0.04 * np.sin(2 * np.pi * 110 * t)
    city = rumble * 1.0 + hum
    for st in (2.0, 7.5):
        pas = lowpass(noise(3.0), 1500) * np.hanning(int(3.0 * RATE)) * 0.5
        city[int(st * RATE):int(st * RATE) + len(pas)] += pas[: n - int(st * RATE)]
    xf = int(1.0 * RATE)
    city[:xf] = city[:xf] * np.linspace(0, 1, xf) + city[-xf:] * np.linspace(1, 0, xf)
    save("amb_city", city[:-xf], 0.35)
    # campo: vento + pássaros
    wind = lowpass(noise(d), 650) * (0.55 + 0.45 * np.sin(2 * np.pi * 0.17 * t + 1.0)) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.43 * t))
    field = wind.copy()
    for st in (1.5, 4.2, 6.6, 9.4, 10.6):
        for k in range(rng.integers(2, 5)):
            f0 = rng.uniform(2200, 3800)
            ch = sweep(f0, f0 * rng.uniform(1.15, 1.5), 0.09) * np.hanning(int(0.09 * RATE)) * 0.06
            s = int((st + k * 0.13) * RATE)
            field[s:s + len(ch)] += ch
    field[:xf] = field[:xf] * np.linspace(0, 1, xf) + field[-xf:] * np.linspace(1, 0, xf)
    save("amb_field", field[:-xf], 0.35)


if __name__ == "__main__":
    make_sfx()
    make_music()
    make_ambient()
    print("Áudio gerado em", os.path.normpath(OUT))
