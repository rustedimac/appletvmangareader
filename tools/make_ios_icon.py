#!/usr/bin/env python3
"""Builds the iPhone/iPad app icon from the tvOS App Store icon layers.

Run from the repo root after tools/make_brand_assets.py:
    python3 tools/make_ios_icon.py
Flattens back/middle/front, center-crops to a square and writes a single
1024x1024 opaque PNG to App/Sources-iOS/Assets.xcassets/AppIcon.appiconset.
"""
import json, os
from PIL import Image

STACK = ("App/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets/"
         "App Icon - App Store.imagestack")
OUT = "App/Sources-iOS/Assets.xcassets/AppIcon.appiconset"

def layer(name):
    return Image.open(f"{STACK}/{name.title()}.imagestacklayer/Content.imageset/{name}.png").convert("RGBA")

img = layer("back")
for name in ("middle", "front"):
    img = Image.alpha_composite(img, layer(name))
w, h = img.size
side = min(w, h)
img = img.crop(((w - side) // 2, (h - side) // 2, (w + side) // 2, (h + side) // 2))
img = img.resize((1024, 1024), Image.LANCZOS).convert("RGB")
os.makedirs(OUT, exist_ok=True)
img.save(f"{OUT}/icon-1024.png")
json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal",
                       "platform": "ios", "size": "1024x1024"}],
           "info": {"author": "xcode", "version": 1}},
          open(f"{OUT}/Contents.json", "w"), indent=2)
