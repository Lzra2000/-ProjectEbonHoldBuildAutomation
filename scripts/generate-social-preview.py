#!/usr/bin/env python3
"""Generate .github/social-preview.png (1200x630) for GitHub repo branding."""

import os
from PIL import Image, ImageDraw, ImageFont

W, H = 1200, 630
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    ".github",
    "social-preview.png",
)

# EbonBuilds palette (banner.svg / generate-media.py)
BG_TOP = (11, 11, 16)
BG_MID = (16, 16, 24)
BG_BOT = (10, 10, 14)
GOLD = (201, 161, 90)
GOLD_LIGHT = (232, 207, 148)
TEAL = (92, 196, 164)
TEAL_GLOW = (126, 224, 194)
MUTED = (154, 154, 168)
DIM = (110, 110, 124)
BORDER = (38, 38, 47)
BORDER_LIGHT = (58, 58, 70)


def _gradient_bg(draw):
    for y in range(H):
        t = y / (H - 1)
        if t < 0.55:
            f = t / 0.55
            r = int(BG_TOP[0] + (BG_MID[0] - BG_TOP[0]) * f)
            g = int(BG_TOP[1] + (BG_MID[1] - BG_TOP[1]) * f)
            b = int(BG_TOP[2] + (BG_MID[2] - BG_TOP[2]) * f)
        else:
            f = (t - 0.55) / 0.45
            r = int(BG_MID[0] + (BG_BOT[0] - BG_MID[0]) * f)
            g = int(BG_MID[1] + (BG_BOT[1] - BG_MID[1]) * f)
            b = int(BG_MID[2] + (BG_BOT[2] - BG_MID[2]) * f)
        draw.line([(0, y), (W, y)], fill=(r, g, b))


def _load_font(size, bold=False):
    candidates = [
        "C:/Windows/Fonts/georgiab.ttf" if bold else "C:/Windows/Fonts/georgia.ttf",
        "C:/Windows/Fonts/timesbd.ttf" if bold else "C:/Windows/Fonts/times.ttf",
        "C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf",
    ]
    for path in candidates:
        if os.path.isfile(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def _draw_rune_anvil(draw, cx, cy):
    glow_r = 155
    for r in range(glow_r, 60, -8):
        alpha = int(18 * (1 - (r - 60) / (glow_r - 60)))
        draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            outline=TEAL_GLOW + (alpha,),
            width=2,
        )
    for radius, opacity in ((108, 76), (95, 217), (82, 102)):
        draw.ellipse(
            [cx - radius, cy - radius, cx + radius, cy + radius],
            outline=TEAL + (opacity,),
            width=2 if radius == 95 else 1,
        )
    # tick marks
    for angle in (0, 90, 180, 270, 45, 135, 225, 315):
        import math

        rad = math.radians(angle)
        x1 = cx + 95 * math.cos(rad)
        y1 = cy + 95 * math.sin(rad)
        x2 = cx + 108 * math.cos(rad)
        y2 = cy + 108 * math.sin(rad)
        draw.line([(x1, y1), (x2, y2)], fill=TEAL + (153,), width=2)

    # anvil silhouette
    draw.polygon(
        [(cx - 50, cy + 15), (cx + 50, cy + 15), (cx + 41, cy + 33), (cx - 41, cy + 33)],
        fill=(28, 28, 38),
        outline=TEAL,
    )
    draw.polygon(
        [(cx - 24, cy + 33), (cx + 24, cy + 33), (cx + 28, cy + 55), (cx - 28, cy + 55)],
        fill=(28, 28, 38),
        outline=TEAL,
    )
    draw.rectangle([cx - 37, cy + 55, cx + 37, cy + 64], fill=(28, 28, 38), outline=TEAL)
    draw.polygon(
        [(cx - 50, cy + 15), (cx - 50, cy), (cx - 6, cy - 9), (cx - 6, cy + 15)],
        fill=(28, 28, 38),
        outline=TEAL,
    )
    draw.polygon(
        [(cx - 6, cy - 1), (cx + 45, cy - 1), (cx + 57, cy + 8), (cx + 57, cy + 15), (cx - 6, cy + 15)],
        fill=(28, 28, 38),
        outline=TEAL,
    )
    draw.ellipse([cx - 4, cy - 32, cx + 4, cy - 24], fill=TEAL_GLOW)
    draw.ellipse([cx - 16, cy - 23, cx - 10, cy - 17], fill=TEAL_GLOW + (180,))
    draw.ellipse([cx + 11, cy - 26, cx + 16, cy - 21], fill=TEAL_GLOW + (153,))


def _draw_gold_title(draw, x, y, text):
    title_font = _load_font(96, bold=True)
    # subtle shadow
    draw.text((x + 3, y + 3), text, font=title_font, fill=(0, 0, 0, 120))
    # gold gradient simulation: light layer offset
    draw.text((x - 1, y - 1), text, font=title_font, fill=GOLD_LIGHT)
    draw.text((x, y), text, font=title_font, fill=GOLD)
    bbox = draw.textbbox((x, y), text, font=title_font)
    line_y = bbox[3] + 14
    draw.line([(x, line_y), (x + 520, line_y)], fill=GOLD + (153,), width=2)
    return line_y


def _draw_corner_accents(draw):
    s = 28
    m = 18
    corners = [
        [(m, m + s), (m, m), (m + s, m)],
        [(W - m - s, m), (W - m, m), (W - m, m + s)],
        [(W - m, H - m - s), (W - m, H - m), (W - m - s, H - m)],
        [(m + s, H - m), (m, H - m), (m, H - m - s)],
    ]
    for pts in corners:
        draw.line(pts, fill=GOLD + (140,), width=2)


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    im = Image.new("RGBA", (W, H), BG_TOP + (255,))
    draw = ImageDraw.Draw(im)
    _gradient_bg(draw)

    draw.rectangle([1, 1, W - 2, H - 2], outline=BORDER, width=3)
    draw.rectangle([6, 6, W - 7, H - 7], outline=BORDER_LIGHT, width=1)

    _draw_rune_anvil(draw, 240, H // 2)

    title_x, title_y = 430, 195
    line_y = _draw_gold_title(draw, title_x, title_y, "EbonBuilds")

    sub_font = _load_font(28)
    tag_font = _load_font(20)
    draw.text(
        (title_x, line_y + 28),
        "Echo automation for ProjectEbonhold",
        font=sub_font,
        fill=MUTED,
    )
    draw.text(
        (title_x, line_y + 72),
        "Define a build once. Every choice screen is scored, decided, and logged.",
        font=tag_font,
        fill=DIM,
    )

    # badge
    badge = "WoW 3.3.5a  ·  WotLK AddOn"
    badge_font = _load_font(18, bold=True)
    bb = draw.textbbox((0, 0), badge, font=badge_font)
    bw, bh = bb[2] - bb[0] + 36, bb[3] - bb[1] + 20
    bx, by = title_x, line_y + 118
    draw.rounded_rectangle(
        [bx, by, bx + bw, by + bh],
        radius=8,
        fill=(18, 28, 24, 220),
        outline=TEAL + (180,),
        width=1,
    )
    draw.text((bx + 18, by + 8), badge, font=badge_font, fill=TEAL_GLOW)

    _draw_corner_accents(draw)
    im.convert("RGB").save(OUT, "PNG", optimize=True)
    print("Wrote %s (%dx%d)" % (OUT, W, H))


if __name__ == "__main__":
    main()
