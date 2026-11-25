#!/usr/bin/env python3
"""Draws the tvOS app icon layers and Top Shelf images (original artwork).

Run from the repo root: python3 tools/make_brand_assets.py
Writes App/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets.
Needs Pillow.
"""
import json, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = "App/Resources/Assets.xcassets"
BRAND = os.path.join(ROOT, "App Icon & Top Shelf Image.brandassets")
SS = 3  # supersampling factor for smooth edges

TOP = (38, 26, 92)       # deep indigo
BOTTOM = (214, 56, 110)  # warm magenta
INK = (24, 20, 40)
PAPER = (250, 247, 240)
ACCENT = (255, 196, 61)  # amber


def gradient(w, h, top=TOP, bottom=BOTTOM):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return img


def halftone(img, spacing, radius, color, alpha):
    """Light screentone dots, a nod to manga printing."""
    over = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    w, h = img.size
    for j, y in enumerate(range(0, h + spacing, spacing)):
        off = spacing // 2 if j % 2 else 0
        for x in range(-spacing, w + spacing, spacing):
            r = radius * (0.35 + 0.65 * y / h)
            d.ellipse([x + off - r, y - r, x + off + r, y + r], fill=color + (alpha,))
    return Image.alpha_composite(img.convert("RGBA"), over)


def spread(w, h):
    """An open two-page spread with panel borders, drawn on transparency."""
    s = SS
    img = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pw, ph = int(w * 0.30) * s, int(h * 0.62) * s
    cx, cy = w * s // 2, int(h * 0.5) * s
    gap = 0
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ds = ImageDraw.Draw(shadow)
    ds.rounded_rectangle([cx - pw - gap, cy - ph // 2 + 18 * s, cx + pw + gap, cy + ph // 2 + 18 * s],
                         radius=14 * s, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(16 * s))
    img = Image.alpha_composite(img, shadow)
    d = ImageDraw.Draw(img)
    for side in (-1, 1):
        x0 = cx - pw if side < 0 else cx
        x1 = cx if side < 0 else cx + pw
        d.rounded_rectangle([x0, cy - ph // 2, x1, cy + ph // 2], radius=12 * s, fill=PAPER)
        # panels
        m = 16 * s
        lw = 5 * s
        inner = [x0 + m, cy - ph // 2 + m, x1 - m, cy + ph // 2 - m]
        ix0, iy0, ix1, iy1 = inner
        hh = (iy1 - iy0)
        cut1 = iy0 + int(hh * (0.38 if side < 0 else 0.55))
        d.rectangle([ix0, iy0, ix1, cut1 - m // 2], outline=INK, width=lw)
        if side < 0:
            mid = ix0 + int((ix1 - ix0) * 0.45)
            d.rectangle([ix0, cut1 + m // 2, mid - m // 4, iy1], outline=INK, width=lw)
            d.rectangle([mid + m // 4, cut1 + m // 2, ix1, iy1], outline=INK, width=lw)
        else:
            d.rectangle([ix0, cut1 + m // 2, ix1, iy1], outline=INK, width=lw)
    # spine shading, so the two pages read as one spread
    d.line([cx, cy - ph // 2, cx, cy + ph // 2], fill=(200, 196, 188), width=3 * s)
    return img.resize((w, h), Image.LANCZOS)


def bubble(w, h, scale=1.0):
    """A speech bubble with a burst of motion lines, on transparency."""
    s = SS
    img = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bw, bh = int(w * 0.26 * scale) * s, int(h * 0.30 * scale) * s
    cx, cy = int(w * 0.66) * s, int(h * 0.30) * s
    box = [cx - bw // 2, cy - bh // 2, cx + bw // 2, cy + bh // 2]
    tail = [(cx - bw // 5, cy + bh // 3), (cx - bw // 2 - 10 * s, cy + bh // 2 + 40 * s), (cx, cy + bh // 2 - 6 * s)]
    lw = 7 * s
    d.ellipse([box[0] - lw, box[1] - lw, box[2] + lw, box[3] + lw], fill=INK)
    d.line(tail + [tail[0]], fill=INK, width=lw * 2, joint="curve")
    d.ellipse(box, fill=ACCENT)
    d.polygon(tail, fill=ACCENT)
    # three dots: "…" — reading in progress
    r = int(bw * 0.07)
    for i in (-1, 0, 1):
        x = cx + i * int(bw * 0.22)
        d.ellipse([x - r, cy - r, x + r, cy + r], fill=INK)
    return img.resize((w, h), Image.LANCZOS)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)
        f.write("\n")


INFO = {"author": "xcode", "version": 1}


def imagestack(name, size, scales):
    w, h = size
    base = os.path.join(BRAND, f"{name}.imagestack")
    layers = [("Front", lambda W, H: bubble(W, H)),
              ("Middle", lambda W, H: spread(W, H)),
              ("Back", lambda W, H: halftone(gradient(W, H), max(8, W // 40), max(2, W // 260), (255, 255, 255), 28).convert("RGB"))]
    write_json(os.path.join(base, "Contents.json"),
               {"info": INFO, "layers": [{"filename": f"{n}.imagestacklayer"} for n, _ in layers]})
    for n, draw in layers:
        layer = os.path.join(base, f"{n}.imagestacklayer")
        write_json(os.path.join(layer, "Contents.json"), {"info": INFO})
        images = []
        for sc in scales:
            fn = f"{n.lower()}{'' if sc == 1 else f'@{sc}x'}.png"
            save(draw(w * sc, h * sc), os.path.join(layer, "Content.imageset", fn))
            images.append({"filename": fn, "idiom": "tv", "scale": f"{sc}x"})
        write_json(os.path.join(layer, "Content.imageset", "Contents.json"), {"images": images, "info": INFO})


def font(size):
    try:
        return ImageFont.truetype("/System/Library/Fonts/Avenir Next.ttc", size, index=8)  # Heavy
    except OSError:
        return ImageFont.load_default()


def top_shelf(name, size):
    w, h = size
    base = os.path.join(BRAND, f"{name}.imageset")
    images = []
    for sc in (1, 2):
        W, H = w * sc, h * sc
        img = halftone(gradient(W, H), max(10, W // 90), max(2, W // 700), (255, 255, 255), 24)
        # spreads fanned across the right side
        tile_w = int(H * 0.85)
        start = W // 2
        for i in range(3):
            sp = spread(tile_w, H)
            y = int(H * (0.06 if i % 2 else -0.02))
            img.alpha_composite(sp, (start + int(i * tile_w * 0.62), y))
        b = bubble(tile_w, H, scale=0.9)
        img.alpha_composite(b, (start + int(tile_w * 0.15), -int(H * 0.02)))
        d = ImageDraw.Draw(img)
        x = int(W * 0.07)
        d.text((x, int(H * 0.36)), "Manga Reader", font=font(int(H * 0.16)), fill=PAPER, anchor="lm")
        d.text((x, int(H * 0.56)), "Kavita and Suwayomi on your TV", font=font(int(H * 0.065)),
               fill=(255, 255, 255, 200), anchor="lm")
        fn = f"{name.lower().replace(' ', '_')}{'' if sc == 1 else '@2x'}.png"
        save(img.convert("RGB"), os.path.join(base, fn))
        images.append({"filename": fn, "idiom": "tv", "scale": f"{sc}x"})
    write_json(os.path.join(base, "Contents.json"), {"images": images, "info": INFO})


def main():
    write_json(os.path.join(ROOT, "Contents.json"), {"info": INFO})
    write_json(os.path.join(BRAND, "Contents.json"), {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
            {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
        ],
        "info": INFO,
    })
    imagestack("App Icon", (400, 240), (1, 2))
    imagestack("App Icon - App Store", (1280, 768), (1,))
    top_shelf("Top Shelf Image", (1920, 720))
    top_shelf("Top Shelf Image Wide", (2320, 720))


if __name__ == "__main__":
    main()
