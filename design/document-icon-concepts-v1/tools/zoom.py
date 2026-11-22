"""Pixel-inspection sheet: shows 16 px and 32 px renders enlarged with
nearest-neighbour sampling, on light and dark backgrounds.
Usage: python3 -I tools/zoom.py <png-root>/<direction> <out.png> [ids...]"""
import sys, os
from PIL import Image, ImageDraw

root, out = sys.argv[1], sys.argv[2]
ids = sys.argv[3:] or sorted(os.listdir(root))
cell = 8 * 16 + 24 + 4 * 32 + 24
W, H = 24 + len(ids) * cell, 2 * (128 + 40) + 24
sheet = Image.new('RGBA', (W, H), (255, 255, 255, 255))
d = ImageDraw.Draw(sheet)
for row, bg in enumerate([(236, 236, 236, 255), (30, 30, 32, 255)]):
    y0 = 12 + row * (128 + 40)
    d.rectangle([0, y0 - 12, W, y0 + 128 + 28], fill=bg)
    for i, fid in enumerate(ids):
        x = 24 + i * cell
        for px, scale in ((16, 8), (32, 4)):
            p = os.path.join(root, fid, f'{fid}-{px}.png')
            if not os.path.exists(p):
                continue
            im = Image.open(p).convert('RGBA').resize((px * scale, px * scale), Image.NEAREST)
            sheet.alpha_composite(im, (x, y0))
            x += px * scale + 24
        d.text((24 + i * cell, y0 + 132), fid, fill=(128, 128, 128, 255))
sheet.save(out)
