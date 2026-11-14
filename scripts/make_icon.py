"""Génère l'icône NotchFlow (Support/AppIcon.png, 1024×1024).

Usage : python scripts/make_icon.py
Dessin en 4096 px puis réduction, pour un anticrénelage propre.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 4                      # facteur de suréchantillonnage
W = 1024 * S
OUT = Path(__file__).resolve().parent.parent / "Support" / "AppIcon.png"


def px(v):
    return int(v * S)


def rounded_mask(box, radius):
    m = Image.new("L", (W, W), 0)
    ImageDraw.Draw(m).rounded_rectangle([px(c) for c in box], radius=px(radius), fill=255)
    return m


def vertical_gradient(top, bottom):
    g = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((W, W), Image.BICUBIC)


def blob(center, radius, color, blur):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    cx, cy = center
    ImageDraw.Draw(layer).ellipse(
        [px(cx - radius), px(cy - radius), px(cx + radius), px(cy + radius)], fill=color
    )
    return layer.filter(ImageFilter.GaussianBlur(px(blur)))


def notch_path(x0, y0, w, h, ear, r):
    """Contour du notch : oreilles concaves en haut, coins arrondis en bas."""
    pts = []

    def quad(p0, c, p1, n=40):
        for i in range(n + 1):
            t = i / n
            x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t ** 2 * p1[0]
            y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t ** 2 * p1[1]
            pts.append((px(x), px(y)))

    x1 = x0 + w
    y1 = y0 + h
    quad((x0, y0), (x0 + ear, y0), (x0 + ear, y0 + ear))
    quad((x0 + ear, y1 - r), (x0 + ear, y1), (x0 + ear + r, y1))
    quad((x1 - ear - r, y1), (x1 - ear, y1), (x1 - ear, y1 - r))
    quad((x1 - ear, y0 + ear), (x1 - ear, y0), (x1, y0))
    return pts


def main():
    # --- Fond : squircle macOS (grille 824 px centrée) -------------------------
    box = (100, 100, 924, 924)
    squircle = rounded_mask(box, 186)

    base = vertical_gradient((38, 20, 92), (6, 6, 18)).convert("RGBA")
    # Aurores colorées
    for c, r, col, b in [
        ((300, 760), 260, (124, 58, 237, 200), 120),
        ((760, 720), 240, (37, 99, 235, 190), 120),
        ((520, 900), 220, (236, 72, 153, 150), 110),
        ((512, 380), 300, (99, 102, 241, 110), 140),
    ]:
        base = Image.alpha_composite(base, blob(c, r, col, b))

    # --- Rubans « flow » dans la moitié basse --------------------------------
    import math
    ribbons = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ribbons)
    for amp, phase, yb, col, width in [
        (46, 0.0, 640, (167, 139, 250, 210), 26),
        (58, 1.1, 700, (244, 114, 182, 190), 22),
        (40, 2.3, 760, (96, 165, 250, 200), 18),
    ]:
        pts = []
        for i in range(0, 241):
            x = 60 + i * (904 / 240)
            y = yb + amp * math.sin(phase + x / 120) + 18 * math.sin(phase * 2 + x / 47)
            pts.append((px(x), px(y)))
        rd.line(pts, fill=col, width=px(width), joint="curve")
    ribbon_glow = ribbons.filter(ImageFilter.GaussianBlur(px(22)))
    base = Image.alpha_composite(base, ribbon_glow)
    base = Image.alpha_composite(base, ribbons.filter(ImageFilter.GaussianBlur(px(2))))

    # --- Notch ouvert ---------------------------------------------------------
    nx, ny, nw, nh = 237, 100, 550, 330
    ear, rad = 34, 78

    # Lueur sous le notch
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle([px(nx + 40), px(ny + 120), px(nx + nw - 40), px(ny + nh + 40)],
                         radius=px(90), fill=(168, 85, 247, 230))
    glow = glow.filter(ImageFilter.GaussianBlur(px(55)))
    base = Image.alpha_composite(base, glow)

    notch = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    nd = ImageDraw.Draw(notch)
    nd.polygon(notch_path(nx, ny, nw, nh, ear, rad), fill=(0, 0, 0, 255))
    base = Image.alpha_composite(base, notch)

    # Liseré lumineux le long du bas du notch
    rim = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(rim).line(notch_path(nx, ny, nw, nh, ear, rad)[45:-45],
                             fill=(196, 181, 253, 120), width=px(3))
    base = Image.alpha_composite(base, rim.filter(ImageFilter.GaussianBlur(px(1))))

    # Pochette d'album (dégradé) à gauche
    art_box = (nx + ear + 44, ny + 72, nx + ear + 44 + 150, ny + 72 + 150)
    art = vertical_gradient((251, 113, 133), (249, 115, 22)).convert("RGBA")
    art_glow = blob(((art_box[0] + art_box[2]) / 2, (art_box[1] + art_box[3]) / 2), 70,
                    (251, 113, 133, 160), 30)
    base = Image.alpha_composite(base, art_glow)
    base.paste(art, (0, 0), rounded_mask(art_box, 30))
    # petite note de musique stylisée
    d = ImageDraw.Draw(base)
    cx, cy = (art_box[0] + art_box[2]) / 2, (art_box[1] + art_box[3]) / 2
    d.ellipse([px(cx - 30), px(cy + 8), px(cx - 2), px(cy + 34)], fill=(255, 255, 255, 235))
    d.rectangle([px(cx - 6), px(cy - 36), px(cx + 1), px(cy + 22)], fill=(255, 255, 255, 235))
    d.polygon([(px(cx - 6), px(cy - 36)), (px(cx + 30), px(cy - 24)),
               (px(cx + 30), px(cy - 10)), (px(cx - 6), px(cy - 22))], fill=(255, 255, 255, 235))

    # Égaliseur à droite
    bars = [62, 112, 84, 128, 70]
    colors = [(129, 140, 248), (167, 139, 250), (232, 121, 249), (244, 114, 182), (96, 165, 250)]
    bw, gap = 22, 16
    total = len(bars) * bw + (len(bars) - 1) * gap
    bx = nx + nw - ear - 50 - total
    mid = (art_box[1] + art_box[3]) / 2
    for i, (h, col) in enumerate(zip(bars, colors)):
        x = bx + i * (bw + gap)
        d.rounded_rectangle([px(x), px(mid - h / 2), px(x + bw), px(mid + h / 2)],
                            radius=px(bw / 2), fill=col + (255,))

    # Barre de progression
    py = art_box[3] + 38
    left, right = nx + ear + 44, nx + nw - ear - 50
    d.rounded_rectangle([px(left), px(py), px(right), px(py + 12)],
                        radius=px(6), fill=(255, 255, 255, 50))
    d.rounded_rectangle([px(left), px(py), px(left + (right - left) * 0.55), px(py + 12)],
                        radius=px(6), fill=(255, 255, 255, 235))

    # Reflet supérieur subtil sur le squircle
    sheen = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).rounded_rectangle([px(c) for c in box], radius=px(186),
                                            outline=(255, 255, 255, 40), width=px(4))
    base = Image.alpha_composite(base, sheen)

    # --- Découpe + ombre portée ---------------------------------------------
    icon = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    icon.paste(base, (0, 0), squircle)

    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    shadow_mask = rounded_mask((100, 112, 924, 936), 186).filter(ImageFilter.GaussianBlur(px(18)))
    shadow.paste((0, 0, 0, 110), (0, 0), shadow_mask)
    final = Image.alpha_composite(shadow, icon)

    final = final.resize((1024, 1024), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    final.save(OUT)
    print(f"Icône écrite : {OUT}")


if __name__ == "__main__":
    main()
