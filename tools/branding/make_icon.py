"""TerraFront application icon (own work, AGPL-3.0): the globe-and-front mark of the main menu on a
dark rounded tile. Writes godot/icon.png (512 px, window icon) and godot/icon.ico (16-256 px, Windows
executable). Usage (repo root): python3 tools/branding/make_icon.py   (needs Pillow)"""
import math
from PIL import Image, ImageDraw

BG = (27, 26, 24, 255)        # UITheme.BG #1b1a18
TILE = (36, 34, 31, 255)
TEXT = (242, 239, 232)        # UITheme.TEXT #f2efe8
ACCENT = (213, 139, 103)      # UITheme.ACCENT #d58b67
S = 2048                      # drawn large, then downsampled (anti-aliasing)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)


GLOBE = mix(TILE, ACCENT, 0.16)


def draw() -> Image.Image:
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([S * 0.03, S * 0.03, S * 0.97, S * 0.97], radius=S * 0.2, fill=TILE)
    c = S / 2
    r = S * 0.34
    lw = int(r * 0.09)
    d.ellipse([c - r, c - r, c + r, c + r], fill=GLOBE)
    d.ellipse([c - r, c - r, c + r, c + r], outline=mix(GLOBE, TEXT, 0.85), width=lw)
    thin = int(lw * 0.6)
    for k in (-0.45, 0.0, 0.45):
        y = c + r * k
        half = math.sqrt(max(0.0, 1 - k * k)) * r
        pts = [(c - half + 2 * half * i / 32, y + math.sin(i / 32 * math.pi) * r * 0.08) for i in range(33)]
        d.line(pts, fill=mix(GLOBE, TEXT, 0.5), width=thin, joint="curve")
    mer = [(c + math.cos(-math.pi / 2 + math.pi * i / 48) * r * 0.42, c + math.sin(-math.pi / 2 + math.pi * i / 48) * r)
           for i in range(49)]
    d.line(mer, fill=mix(GLOBE, TEXT, 0.5), width=thin, joint="curve")
    front = [(-0.95, 0.25), (-0.4, -0.15), (-0.05, 0.2), (0.4, -0.3), (0.92, -0.05)]
    pts = [(c + x * r, c + y * r) for x, y in front]
    w = int(lw * 1.6)
    d.line(pts, fill=ACCENT + (255,), width=w, joint="curve")
    for p in pts:
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=ACCENT + (255,))
    return im


if __name__ == "__main__":
    big = draw()
    big.resize((512, 512), Image.LANCZOS).save("godot/icon.png")
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    big.resize((256, 256), Image.LANCZOS).save("godot/icon.ico", sizes=sizes)
    print("wrote godot/icon.png, godot/icon.ico")
