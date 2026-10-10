"""Renders the app's icon files from logo_dark.svg and logo_simple.svg.

Run from this directory after build_logo.py, then `dart run flutter_launcher_icons`
at the repository root. Needs ImageMagick (`magick`, with librsvg) and Pillow.
"""
import math
import os
import subprocess

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
BG = (14, 21, 18)  # #0E1512, also adaptive_icon_background in pubspec.yaml

# Where the launcher mark is centred, in the logo's 2048 viewBox: halfway between
# the bamboo and the hotend's heatsink across, the B's axis down.
FULL_CENTRE = ((913 + 1035) / 2, 1206)

# flutter_launcher_icons insets the foreground and monochrome layers by 16 % of
# 108 dp, so their PNG spans the middle 73.44 dp. The mark must stay inside the
# 72 dp the launcher masks show, hence this share of the PNG's half-width.
LAYER_FILL = 36 / (108 * 0.68 / 2)


def rasterise(svg):
    subprocess.run(['magick', '-background', 'none', '-density', '400', svg,
                    'PNG32:/tmp/_logo.png'], check=True)
    im = Image.open('/tmp/_logo.png').convert('RGBA')
    return im, im.width / 2048


def mass_centre(im, k):
    a = im.split()[3].load()
    sx = sy = n = 0
    for y in range(0, im.height, 4):
        for x in range(0, im.width, 4):
            if a[x, y] > 40:
                sx += x
                sy += y
                n += 1
    return sx / n / k, sy / n / k


def place(im, k, centre, size, radius, background=None, tint=None):
    """The mark scaled so its farthest pixel from `centre` is `radius` px away,
    with `centre` at the middle of a `size` px square."""
    box = im.split()[3].getbbox()
    mark = im.crop(box)
    cx, cy = centre[0] * k - box[0], centre[1] * k - box[1]
    a = mark.split()[3].load()
    far = max(math.dist((cx, cy), (x, y))
              for y in range(0, mark.height, 3) for x in range(0, mark.width, 3)
              if a[x, y] > 40)
    s = radius / far
    mark = mark.resize((round(mark.width * s), round(mark.height * s)), Image.LANCZOS)
    if tint:
        solid = Image.new('RGBA', mark.size, tint + (255,))
        solid.putalpha(mark.split()[3])
        mark = solid
    out = Image.new('RGBA', (size, size), (background or (0, 0, 0)) + ((255,) if background else (0,)))
    out.alpha_composite(mark, (round(size / 2 - cx * s), round(size / 2 - cy * s)))
    return out


full, kf = rasterise('logo_dark.svg')
simple, ks = rasterise('logo_simple.svg')
simple_centre = mass_centre(simple, ks)

# adaptive layers (1024 px each, the generator scales them per density)
place(full, kf, FULL_CENTRE, 1024, 512 * LAYER_FILL).save(
    f'{ROOT}/assets/icon/icon_foreground.png')
place(simple, ks, simple_centre, 1024, 512 * LAYER_FILL, tint=(255, 255, 255)).save(
    f'{ROOT}/assets/icon/icon_monochrome.png')

# legacy square icon (pre-26 launchers): the 108 dp layout, background included
place(full, kf, FULL_CENTRE, 1024, 1024 * 36 / 108, background=BG).save(
    f'{ROOT}/assets/icon/icon.png')

# Google Play, 512 px; Play rounds the corners itself
place(full, kf, FULL_CENTRE, 512, 512 * 0.38, background=BG).convert('RGB').save(
    f'{ROOT}/docs/store-assets/play-icon-512.png')

# status bar: white silhouette filling 22 of 24 dp
glyph = simple.split()[3].crop(simple.split()[3].getbbox())
for density, scale in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
    canvas, live = round(24 * scale), 22 * scale
    f = live / max(glyph.size)
    g = glyph.resize((round(glyph.width * f), round(glyph.height * f)), Image.LANCZOS)
    out = Image.new('RGBA', (canvas, canvas), (255, 255, 255, 0))
    a = Image.new('L', (canvas, canvas), 0)
    a.paste(g, ((canvas - g.width) // 2, (canvas - g.height) // 2))
    out.putalpha(a)
    out.save(f'{ROOT}/android/app/src/main/res/drawable-{density}/ic_stat_notify.png', optimize=True)

# Google Play feature graphic, 1024x500: mark on the left, name and line on the
# right, the text sized to the room it has rather than to a fixed point size
W, H = 1024, 500
banner = Image.new('RGB', (W, H), BG)
glow = Image.new('L', (W, H), 0)
ImageDraw.Draw(glow).ellipse((40, 20, 440, 480), fill=38)   # soft lift behind the mark
banner.paste(Image.new('RGB', (W, H), (40, 70, 52)), (0, 0), glow.filter(ImageFilter.GaussianBlur(70)))
mark = place(full, kf, FULL_CENTRE, 400, 190)
banner.paste(mark, (40, 50), mark)
font = lambda w, s: ImageFont.truetype(f'{ROOT}/assets/fonts/Manrope-{w}.ttf', s)
d = ImageDraw.Draw(banner)
left, right = 470, W - 60
lines = ('Companion for a self-hosted', 'Bambu Lab printer manager')
size = 110
while d.textlength('Bambuddy', font=font(800, size)) > right - left:
    size -= 2
sub = 40
while max(d.textlength(l, font=font(600, sub)) for l in lines) > right - left:
    sub -= 1
title_h, gap, line_h = size, 26, round(sub * 1.3)
top = (H - (title_h + gap + line_h * 2)) // 2
d.text((left, top), 'Bambuddy', font=font(800, size), fill=(242, 245, 243), anchor='lt')
for k, l in enumerate(lines):
    d.text((left + 3, top + title_h + gap + k * line_h), l, font=font(600, sub), fill=(52, 196, 110), anchor='lt')
banner.save(f'{ROOT}/docs/store-assets/play-feature-1024x500.png')
