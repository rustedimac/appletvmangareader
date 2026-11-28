# Builds content/Manga/Pepper&Carrot/*.cbz (episodes 1-6, CC BY 4.0, David Revoy) and content/Books/Pepper&Carrot PDF/Pepper&Carrot Ep.01.pdf.
# Needs Pillow (python3 -m venv venv && venv/bin/pip install Pillow) and $TEST_SERVERS_DIR/dl/episodes.json from https://www.peppercarrot.com/0_sources/episodes.json

import json, os, sys, time, zipfile, urllib.request, urllib.error, io
T = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('TEST_SERVERS_DIR', os.path.expanduser('~/test-servers'))
eps = json.load(open(f"{T}/dl/episodes.json"))[:6]
out = f"{T}/content/Manga/Pepper&Carrot"; os.makedirs(out, exist_ok=True)
raw = f"{T}/dl/pc"; os.makedirs(raw, exist_ok=True)
for i, e in enumerate(eps, 1):
    pages = []
    for p in range(0, e["total_pages"] + 1):
        dst = None
        for ext in ("jpg", "gif", "png"):
            fn = f"en_Pepper-and-Carrot_by-David-Revoy_E{i:02d}P{p:02d}.{ext}"
            cand = f"{raw}/{fn}"
            if os.path.exists(cand): dst = cand; break
            url = f"https://www.peppercarrot.com/0_sources/{e['name']}/low-res/{fn}"
            try:
                urllib.request.urlretrieve(url, cand); time.sleep(0.3); dst = cand; break
            except urllib.error.HTTPError:
                continue
        if dst is None: raise SystemExit(f"missing page {i} {p}")
        if not dst.endswith(".jpg"):
            from PIL import Image
            j = dst.rsplit(".", 1)[0] + ".conv.jpg"
            Image.open(dst).convert("RGB").save(j, quality=90); dst = j
        pages.append(dst)
    title = e["name"].split("_", 1)[1].replace("-", " ")
    ci = f"""<?xml version="1.0" encoding="utf-8"?>
<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <Title>{title}</Title>
  <Series>Pepper&amp;Carrot</Series>
  <Number>{i}</Number>
  <Count>{len(eps)}</Count>
  <Writer>David Revoy</Writer>
  <Penciller>David Revoy</Penciller>
  <Publisher>David Revoy</Publisher>
  <LanguageISO>en</LanguageISO>
  <Manga>No</Manga>
  <PageCount>{len(pages)}</PageCount>
  <Web>https://www.peppercarrot.com</Web>
  <Notes>CC BY 4.0, www.peppercarrot.com - Pepper&amp;Carrot by David Revoy</Notes>
</ComicInfo>
"""
    cbz = f"{out}/Pepper&Carrot Ep.{i:02d}.cbz"
    with zipfile.ZipFile(cbz, "w", zipfile.ZIP_STORED) as z:
        for n, p in enumerate(pages, 1):
            z.write(p, f"{n:03d}.jpg")
        z.writestr("ComicInfo.xml", ci)
    print(cbz, len(pages), e["name"])
    if i == 1:
        from PIL import Image
        ims = [Image.open(p).convert("RGB") for p in pages]
        os.makedirs(f"{T}/content/Books/Pepper&Carrot PDF", exist_ok=True); ims[0].save(f"{T}/content/Books/Pepper&Carrot PDF/Pepper&Carrot Ep.01.pdf", save_all=True, append_images=ims[1:],
                    title="Pepper&Carrot Ep.01: Potion of Flight", author="David Revoy")
