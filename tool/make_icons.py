#!/usr/bin/env python3
"""Draws the app's icons: a navigation arrow pointing up, on a transparent background.

    python3 tool/make_icons.py

Needs Pillow only. The arrow is Material's "navigation" shape with rounded joins (the same geometry as
`branding/logo.svg`), in the brand's green (`AppTheme.brand`); the dev flavor is orange with a "DEV" tag and the beta
flavor green with a "BETA" tag. Every file below is overwritten at its current size, so the sets of sizes stay those of
the platforms' folders. iOS can't have transparency (the App Store refuses an icon with an alpha channel): its icons are
the arrow on white.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent

GREEN = (10, 143, 78)  # 0xFF0A8F4E, AppTheme.brand
ORANGE = (232, 118, 26)
BLACK = (0, 0, 0)

# Material "navigation": tip, left foot, notch, right foot (24 x 24 grid, the notch point doubles as the inner corner)
ARROW = [(12, 2), (4.5, 20.29), (5.21, 21), (12, 18), (18.79, 21), (19.5, 20.29)]
JOIN = 0.55  # radius of the rounded joins, in grid units
GRID_W = 15 + 2 * JOIN
GRID_H = 19 + 2 * JOIN
GRID_LEFT = 4.5 - JOIN
GRID_TOP = 2 - JOIN

BIG = 4096
FONT = ROOT / 'assets/google_fonts/Inter-SemiBold.ttf'


def arrow_mask() -> Image.Image:
    """The arrow alone, cropped to its bounds, as a mask: 4096 high, rounded at every corner."""
    scale = BIG / GRID_H * 0.8
    pad = BIG * 0.1
    pts = [(pad + (x - GRID_LEFT) * scale, pad + (y - GRID_TOP) * scale) for x, y in ARROW]
    mask = Image.new('L', (BIG, BIG), 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon(pts, fill=255)
    r = JOIN * scale
    for (x, y) in pts:
        draw.ellipse((x - r, y - r, x + r, y + r), fill=255)
    for a, b in zip(pts, pts[1:] + pts[:1]):
        # the stroke of the edges: a thick line with round ends
        draw.line([a, b], fill=255, width=round(2 * r))
    return mask.crop(mask.getbbox())


_ARROW = arrow_mask()


def icon(size: int, color, *, height: float, label: str | None = None, background=None) -> Image.Image:
    """An icon of [size] pixels: the arrow [height] (fraction of the side) high, centered, with a tag under it."""
    scale = 4  # drawn four times too big, then reduced
    n = size * scale
    img = Image.new('RGBA', (n, n), background or (0, 0, 0, 0))
    ah = round(n * height)
    aw = round(_ARROW.width * ah / _ARROW.height)
    arrow = _ARROW.resize((aw, ah), Image.LANCZOS)
    if label is None:
        top = (n - ah) // 2
    else:
        pill_h = round(n * 0.2 * height / 0.62)
        gap = round(n * 0.045 * height / 0.62)
        top = (n - (ah + gap + pill_h)) // 2
        pill_w = round(pill_h * (2.9 if len(label) <= 3 else 3.5))
        px = (n - pill_w) // 2
        py = top + ah + gap
        draw = ImageDraw.Draw(img)
        draw.rounded_rectangle((px, py, px + pill_w, py + pill_h), radius=pill_h // 2, fill=color)
        font = ImageFont.truetype(str(FONT), round(pill_h * 0.58))
        draw.text((n // 2, py + pill_h / 2), label, font=font, fill=(255, 255, 255), anchor='mm')
    layer = Image.new('RGBA', (aw, ah), color + (255,))
    layer.putalpha(arrow)
    img.alpha_composite(layer, ((n - aw) // 2, top))
    return img.resize((size, size), Image.LANCZOS)


def save(path: str, img: Image.Image) -> None:
    p = ROOT / path
    img.save(p)
    print(path, img.size)


def resave(path: str, make) -> None:
    """Rewrites an existing PNG at its current size; [make] gets that size."""
    p = ROOT / path
    size = Image.open(p).size[0]
    save(path, make(size))


# What each kind of file shows (fractions of the side)
FULL = 0.62  # a plain icon: web, macOS, Windows, Linux, Play Store, legacy launchers, iOS
SAFE = 0.40  # an adaptive layer: Android crops everything outside the middle 61 %
SAFE_TAGGED = 0.30
MASKABLE = 0.46  # the web's maskable icons keep to the middle 80 %


def main() -> None:
    res = ROOT / 'android/app/src'
    for density in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'):
        main_dir = f'{res}/main/res/mipmap-{density}'
        dev_dir = f'{res}/dev/res/mipmap-{density}'
        beta_dir = f'{res}/beta/res/mipmap-{density}'
        rel = lambda d: str(Path(d).relative_to(ROOT))
        # Adaptive layers: the background is left transparent
        resave(rel(main_dir) + '/ic_launcher_foreground.png', lambda s: icon(s, GREEN, height=SAFE))
        resave(rel(main_dir) + '/ic_launcher_background.png', lambda s: Image.new('RGBA', (s, s), (0, 0, 0, 0)))
        resave(rel(main_dir) + '/ic_launcher_monochrome.png', lambda s: icon(s, BLACK, height=SAFE))
        resave(rel(main_dir) + '/ic_launcher.png', lambda s: icon(s, GREEN, height=FULL))
        resave(rel(dev_dir) + '/ic_launcher_foreground.png', lambda s: icon(s, ORANGE, height=SAFE_TAGGED, label='DEV'))
        resave(rel(dev_dir) + '/ic_launcher_background.png', lambda s: Image.new('RGBA', (s, s), (0, 0, 0, 0)))
        resave(rel(dev_dir) + '/ic_launcher.png', lambda s: icon(s, ORANGE, height=FULL * 0.8, label='DEV'))
        resave(rel(beta_dir) + '/ic_launcher_foreground.png', lambda s: icon(s, GREEN, height=SAFE_TAGGED, label='BETA'))
        resave(rel(beta_dir) + '/ic_launcher_background.png', lambda s: Image.new('RGBA', (s, s), (0, 0, 0, 0)))

    resave('android/app/src/main/play_store_512.png', lambda s: icon(s, GREEN, height=FULL))

    # Web
    resave('web/favicon.png', lambda s: icon(s, GREEN, height=0.9))
    resave('web/icons/Icon-192.png', lambda s: icon(s, GREEN, height=FULL))
    resave('web/icons/Icon-512.png', lambda s: icon(s, GREEN, height=FULL))
    resave('web/icons/Icon-maskable-192.png', lambda s: icon(s, GREEN, height=MASKABLE))
    resave('web/icons/Icon-maskable-512.png', lambda s: icon(s, GREEN, height=MASKABLE))

    # macOS, Linux
    for p in sorted((ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset').glob('app_icon_*.png')):
        resave(str(p.relative_to(ROOT)), lambda s: icon(s, GREEN, height=FULL))
    resave('linux/runner/resources/app_icon.png', lambda s: icon(s, GREEN, height=FULL))

    # iOS: no alpha channel allowed, white behind
    for p in sorted((ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset').glob('*.png')):
        resave(str(p.relative_to(ROOT)),
               lambda s: icon(s, GREEN, height=FULL, background=(255, 255, 255, 255)).convert('RGB'))

    # Windows: one .ico holding the sizes it already has
    ico = ROOT / 'windows/runner/resources/app_icon.ico'
    sizes = sorted(Image.open(ico).info['sizes'])
    biggest = icon(256, GREEN, height=FULL)
    biggest.save(ico, sizes=sizes)
    print('windows/runner/resources/app_icon.ico', sizes)

    # What goes to Google Cloud's consent screen, and the master drawing
    out = ROOT / 'branding'
    out.mkdir(exist_ok=True)
    for s in (1024, 512, 120):
        save(f'branding/logo-{s}.png', icon(s, GREEN, height=FULL))
    save('branding/logo-dev-512.png', icon(512, ORANGE, height=FULL * 0.8, label='DEV'))
    save('branding/logo-beta-512.png', icon(512, GREEN, height=FULL * 0.8, label='BETA'))
    (out / 'logo.svg').write_text(svg(GREEN), encoding='utf-8')


def svg(color) -> str:
    s = 1024 * FULL / GRID_H
    tx = (1024 - GRID_W * s) / 2 - GRID_LEFT * s
    ty = (1024 - GRID_H * s) / 2 - GRID_TOP * s
    hex_color = '#%02X%02X%02X' % color
    d = 'M' + ' L'.join(f'{x} {y}' for x, y in ARROW) + ' Z'
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n'
        f'  <path transform="translate({tx:.2f} {ty:.2f}) scale({s:.4f})" d="{d}" fill="{hex_color}"\n'
        f'        stroke="{hex_color}" stroke-width="{2 * JOIN}" stroke-linejoin="round"/>\n'
        '</svg>\n'
    )


if __name__ == '__main__':
    main()
