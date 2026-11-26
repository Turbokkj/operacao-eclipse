#!/usr/bin/env python3
"""Gera as texturas (albedo, 128x128, tileáveis) do jogo por síntese procedural — originais.
Saída: assets/textures/*.tex (arquivos PNG com extensão .tex: o jogo carrega via Image.load_png_from_buffer,
sem depender do pipeline de importação do editor). Requer: python3 + numpy + Pillow.
Uso: python3 tools/gen_textures.py"""
import io
import os
import numpy as np
from PIL import Image

S = 128
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures")
rng = np.random.default_rng(424242)


def fbm(size=S, octaves=((4, 1.0), (10, 0.5), (24, 0.25), (56, 0.12)), seed=None):
    """Ruído tileável (periódico) por filtragem no domínio da frequência."""
    r = np.random.default_rng(seed) if seed is not None else rng
    out = np.zeros((size, size))
    fy = np.fft.fftfreq(size)[:, None] * size
    fx = np.fft.fftfreq(size)[None, :] * size
    rad = np.sqrt(fx ** 2 + fy ** 2)
    for cells, amp in octaves:
        spec = np.fft.fft2(r.standard_normal((size, size)))
        spec *= np.exp(-(rad / cells) ** 2)
        layer = np.real(np.fft.ifft2(spec))
        layer = (layer - layer.mean()) / (layer.std() + 1e-9)
        out += layer * amp
    return out / (sum(a for _, a in octaves) * 2.2)


def colorize(base, n, var=0.18):
    base = np.array(base, dtype=float)
    img = base[None, None, :] * (1.0 + n[..., None] * var)
    return img


def speckle(amount=0.05):
    return rng.standard_normal((S, S)) * amount


def save(name, arr):
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    buf = io.BytesIO()
    Image.fromarray(arr, "RGB").save(buf, format="PNG", optimize=True)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".tex"), "wb") as f:
        f.write(buf.getvalue())
    print("%-10s %6d bytes" % (name, len(buf.getvalue())))


def bricks(rows=8, per_row=4, mortar=3, tone=(205, 172, 150)):
    img = np.zeros((S, S, 3))
    bh, bw = S // rows, S // per_row
    n = fbm(seed=11)
    for r in range(rows):
        off = (bw // 2) if r % 2 else 0
        for c in range(per_row):
            v = 0.88 + rng.random() * 0.2
            x0, y0 = (c * bw + off) % S, r * bh
            for dx in range(bw):
                for dy in range(bh):
                    img[(y0 + dy) % S, (x0 + dx) % S] = np.array(tone) * v
    for r in range(rows):
        img[(r * bh) % S: (r * bh) % S + mortar, :] = (190, 188, 182)
        off = (bw // 2) if r % 2 else 0
        for c in range(per_row):
            x = (c * bw + off) % S
            img[r * bh: (r + 1) * bh, x: x + mortar] = (190, 188, 182) if x + mortar <= S else img[r * bh: (r + 1) * bh, x: x + mortar]
    return img * (1 + n[..., None] * 0.10)


def main():
    save("grass", colorize((98, 138, 66), fbm(seed=1), 0.22) * (1 + speckle(0.05))[..., None])
    save("dirt", colorize((132, 106, 78), fbm(seed=2), 0.20) * (1 + speckle(0.06))[..., None])
    n = fbm(seed=3)
    pits = (rng.random((S, S)) > 0.992).astype(float) * -0.25
    save("concrete", colorize((176, 176, 172), n, 0.14) * (1 + pits + speckle(0.03))[..., None])
    save("asphalt", colorize((74, 76, 80), fbm(seed=4), 0.10) * (1 + speckle(0.09))[..., None])
    road = colorize((74, 76, 80), fbm(seed=5), 0.10) * (1 + speckle(0.09))[..., None]
    for x in (int(S * 0.06), int(S * 0.92)):      # linhas de borda
        road[:, x:x + 3] = (225, 225, 220)
    cx = S // 2 - 1
    for y0 in range(0, S, S // 2):               # faixa central tracejada
        road[y0:y0 + S // 4, cx:cx + 3] = (240, 205, 80)
    save("road", road)
    save("plaster", colorize((228, 223, 213), fbm(seed=6), 0.07) * (1 + speckle(0.02))[..., None])
    save("brick", bricks())
    # telhado: fileiras de telhas sobrepostas
    roof = np.zeros((S, S, 3))
    base = np.array((205, 152, 132))
    nr = fbm(seed=7)
    for y in range(S):
        row = y // 16
        shade = 0.72 + 0.28 * ((y % 16) / 16.0)
        for x in range(S):
            tile = ((x + (8 if row % 2 else 0)) % 16) / 16.0
            roof[y, x] = base * shade * (0.9 + 0.1 * np.sin(tile * np.pi))
    save("roof", roof * (1 + nr[..., None] * 0.10))
    # madeira: tábuas horizontais com veios
    wood = np.zeros((S, S, 3))
    for p in range(8):
        y0 = p * 16
        tone = np.array((192, 150, 106)) * (0.88 + rng.random() * 0.22)
        grain = fbm(seed=20 + p, octaves=((2, 1.0), (30, 0.6)))
        for y in range(16):
            wood[y0 + y, :, :] = tone[None, :] * (1 + grain[y0 + y, :, None] * 0.18)
        wood[y0:y0 + 1, :, :] = (90, 66, 44)
    save("wood", wood)
    # piso de cerâmica: ladrilhos com rejunte
    tile = np.zeros((S, S, 3))
    for r in range(4):
        for c in range(4):
            v = 0.94 + rng.random() * 0.08
            tile[r * 32:(r + 1) * 32, c * 32:(c + 1) * 32] = np.array((218, 218, 214)) * v
    tile[::32, :] = (150, 150, 146)
    tile[:, ::32] = (150, 150, 146)
    save("tile", tile * (1 + fbm(seed=8)[..., None] * 0.04))
    # metal corrugado: nervuras verticais + manchas de ferrugem
    x = np.arange(S)[None, :]
    rib = 0.80 + 0.20 * np.sin(2 * np.pi * x / 16.0)
    rust = np.clip(fbm(seed=9, octaves=((5, 1.0), (20, 0.5))) - 0.25, 0, 1) * 0.5
    metal = np.array((176, 184, 194))[None, None, :] * rib[..., None] * np.ones((S, S, 1))
    metal = metal * (1 - rust[..., None]) + np.array((150, 90, 58))[None, None, :] * rust[..., None]
    save("metal", metal * (1 + speckle(0.03))[..., None])
    print("Texturas geradas em", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
