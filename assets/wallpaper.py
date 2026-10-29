#!/usr/bin/env python3
"""Gera o papel de parede padrão do AquaOS (estilo Sonoma/aurora).

Depende apenas da biblioteca padrão. É executado em tempo de build pelo
Nix (modules/base.nix) e também funciona manualmente:

    python3 wallpaper.py --out sonoma.png

Não há recursos binários no repositório — o PNG do sistema é construído
aqui, pixel a pixel, e o mesmo gradiente serve de "brand" do sistema.
"""

import argparse
import struct
import zlib

LARGURA, ALTURA = 1920, 1080

# Gradiente "aurora": âmbar (topo) -> rosa -> roxo -> azul profundo (base).
PARADAS = [
    (0.00, (255, 214, 153)),
    (0.35, (244, 130, 168)),
    (0.68, (132, 92, 204)),
    (1.00, (41, 44, 108)),
]


def gradiente(t):
    """Cor interpolada no gradiente (t em [0, 1])."""
    if t <= PARADAS[0][0]:
        return PARADAS[0][1]
    for (t0, c0), (t1, c1) in zip(PARADAS, PARADAS[1:]):
        if t <= t1:
            f = (t - t0) / (t1 - t0)
            return tuple(int(c0[i] + (c1[i] - c0[i]) * f) for i in range(3))
    return PARADAS[-1][1]


def gera_pixels():
    """Linhas da imagem já formatadas para o PNG (filtro 'none')."""
    blocos = bytearray()
    for y in range(ALTURA):
        ny = (y + 0.5) / ALTURA
        blocos += b"\x00"
        for x in range(LARGURA):
            nx = (x + 0.5) / LARGURA
            r, g, b = gradiente(nx * 0.55 + ny * 0.45)
            # Reflexo suave (como o brilho de um vidro do macOS).
            dx, dy = nx - 0.28, ny - 0.22
            d = (dx * dx + dy * dy) ** 0.5
            brilho = max(0.0, 1.0 - d / 0.75) ** 2 * 0.30
            if brilho > 0:
                r = int(r + (255 - r) * brilho)
                g = int(g + (255 - g) * brilho)
                b = int(b + (255 - b) * brilho)
            # Dither leve para evitar banding no gradiente de 8 bits.
            n = ((x * 299 + y * 397) % 5) - 2
            blocos += bytes(
                (
                    max(0, min(255, r + n)),
                    max(0, min(255, g + n)),
                    max(0, min(255, b + n)),
                )
            )
    return bytes(blocos)


def chunk(tipo, dados):
    return (
        struct.pack(">I", len(dados))
        + tipo
        + dados
        + struct.pack(">I", zlib.crc32(tipo + dados) & 0xFFFFFFFF)
    )


def main():
    descricao = __doc__ if __doc__ else "Gera o papel de parede do AquaOS."
    ap = argparse.ArgumentParser(description=descricao)
    ap.add_argument("--out", required=True, help="arquivo PNG de saída")
    args = ap.parse_args()

    ihdr = struct.pack(">IIBBBBB", LARGURA, ALTURA, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(gera_pixels(), 9))
        + chunk(b"IEND", b"")
    )
    with open(args.out, "wb") as arq:
        arq.write(png)
    print(f"Papel de parede gerado: {args.out}")


if __name__ == "__main__":
    main()
