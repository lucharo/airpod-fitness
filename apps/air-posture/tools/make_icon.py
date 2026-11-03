# /// script
# dependencies = ["pillow"]
# ///
"""Draw the 1024px Air Posture app icon: a head on a neck, tilted slightly
forward, over a level line. Run: uv run tools/make_icon.py <out.png>"""
import sys
from PIL import Image, ImageDraw

S = 1024
img = Image.new("RGB", (S, S), (18, 24, 38))
d = ImageDraw.Draw(img)
white, teal = (240, 244, 248), (64, 196, 170)

# level reference line
d.line([(212, 300), (812, 300)], fill=teal, width=28)
# neck and shoulders
d.line([(512, 820), (512, 600)], fill=white, width=64)
d.rounded_rectangle([(282, 800), (742, 880)], radius=40, fill=white)
# head, sitting upright on the neck
d.ellipse([(392, 380), (632, 620)], fill=white)
# earbud
d.ellipse([(560, 470), (610, 520)], fill=teal)

img.save(sys.argv[1])
