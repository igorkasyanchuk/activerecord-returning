#!/usr/bin/env python3
"""Render docs/demo.gif — one screen, three reveals: the count, the rows, the statement.

Everything stays on screen, so the last frame is a complete picture of the gem
rather than the tail of a slideshow.

Drawn at 2x then downsampled so type stays sharp on a retina README.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
OUT_GIF = ROOT / "demo.gif"

LW, LH = 980, 580
DRAW = 2
OUT = 1.4
W, H = int(LW * DRAW), int(LH * DRAW)
OUT_SIZE = (int(LW * OUT), int(LH * OUT))
FPS = 20

BG = (10, 13, 18)
CARD = (21, 26, 33)
CARD_DIM = (17, 21, 27)
BORDER = (48, 55, 64)
HAIR = (34, 40, 48)
TEXT = (233, 238, 244)
MUTED = (150, 159, 170)
DIM = (96, 105, 117)
ACCENT = (86, 180, 233)
ACCENT_SOFT = (36, 74, 96)
AMBER = (226, 172, 84)
GREEN = (126, 211, 156)
RUBY_SYM = (121, 192, 255)
RUBY_NAME = (206, 168, 255)
SQL_KW = (121, 192, 255)
STR = (163, 217, 140)
NUM = (226, 172, 84)

SQL_KEYWORDS = {"UPDATE", "SET", "WHERE", "IN", "SELECT", "FROM", "RETURNING"}

BEFORE = "User.where(role: :admin).update_all(role: :member)"
AFTER_1 = "User.where(role: :admin).update_all_returning("
AFTER_2 = "  { role: :member }, returning: %i[id email])"

TABLE_HEAD = ("id", "email")
TABLE_ROWS = [("1", "ada@example.com"), ("2", "grace@example.com")]

SQL = [
    'UPDATE users SET role = 0',
    'WHERE users.id IN (SELECT users.id FROM users WHERE users.role = 1)',
    'RETURNING id, email',
]

MARGIN = 30
WIN = (MARGIN, 24, LW - MARGIN, LH - 22)
PAD = 30
CONTENT = MARGIN + PAD
CONTENT_R = LW - MARGIN - PAD

TITLE_CY = WIN[1] + 30
SUB_CY = TITLE_CY + 26

PANEL_1 = (CONTENT, SUB_CY + 26, CONTENT_R, SUB_CY + 134)
PANEL_2 = (CONTENT, PANEL_1[3] + 18, CONTENT_R, PANEL_1[3] + 218)
SQL_TOP = PANEL_2[3] + 20


def px(v: float) -> int:
    return int(round(v * DRAW))


def font(path: str, size: float, index: int = 0) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, px(size), index=index)


FONT_TITLE = font("/System/Library/Fonts/SFNS.ttf", 21)
FONT_UI = font("/System/Library/Fonts/SFNS.ttf", 14)
FONT_SM = font("/System/Library/Fonts/SFNS.ttf", 12)
FONT_CODE = font("/System/Library/Fonts/SFNSMono.ttf", 14)
FONT_CODE_SM = font("/System/Library/Fonts/SFNSMono.ttf", 12.5)
FONT_NUM = font("/System/Library/Fonts/SFNSMono.ttf", 15)


def mix(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def box(x0, y0, x1, y1):
    return (px(x0), px(y0), px(x1), px(y1))


def rounded(draw, coords, radius, fill, outline=None, width=1.0):
    draw.rounded_rectangle(box(*coords), radius=px(radius), fill=fill, outline=outline, width=max(1, px(width)))


_RASTER_INK = {}


def raster_ink(s, font_, thresh=48):
    """Painted-pixel bbox for a top-left draw at (0, 0); SFNS ink sits off-center in the em-box."""
    key = (s, id(font_), thresh)
    hit = _RASTER_INK.get(key)
    if hit is not None:
        return hit
    pad = 80
    im = Image.new("L", (pad * 2 + 1400, pad * 2 + 160), 0)
    ImageDraw.Draw(im).text((pad, pad), s, font=font_, fill=255)
    mask = im.point(lambda p: 255 if p >= thresh else 0)
    bb = mask.getbbox()
    hit = (0, 0, 0, 0) if bb is None else (bb[0] - pad, bb[1] - pad, bb[2] - pad, bb[3] - pad)
    _RASTER_INK[key] = hit
    return hit


def t_center(draw, cx, cy, s, font_, fill):
    l, t0, r, b = raster_ink(s, font_)
    draw.text((px(cx) - (l + r) / 2, px(cy) - (t0 + b) / 2), s, font=font_, fill=fill)


def t_left(draw, x, cy, s, font_, fill):
    l, t0, r, b = raster_ink(s, font_)
    draw.text((px(x) - l, px(cy) - (t0 + b) / 2), s, font=font_, fill=fill)


def ink_w(s, font_) -> float:
    l, _, r, _ = raster_ink(s, font_)
    return (r - l) / DRAW


def code_w(draw, s, font_) -> float:
    return draw.textlength(s, font=font_) / DRAW


def tokenize_ruby(line: str):
    tokens, i, n = [], 0, len(line)
    while i < n:
        ch = line[i]
        if ch in " \t":
            j = i
            while j < n and line[j] in " \t":
                j += 1
            tokens.append((line[i:j], None))
            i = j
        elif line[i:i + 2] == "%i":
            j = line.find("]", i)
            j = n if j == -1 else j + 1
            tokens.append((line[i:j], RUBY_SYM))
            i = j
        elif ch == ":":
            j = i + 1
            while j < n and (line[j].isalnum() or line[j] == "_"):
                j += 1
            tokens.append((line[i:j], RUBY_SYM))
            i = j
        elif ch.isalnum() or ch == "_":
            j = i
            while j < n and (line[j].isalnum() or line[j] == "_"):
                j += 1
            word = line[i:j]
            color = RUBY_NAME if word[:1].isupper() else TEXT
            if word in {"update_all_returning", "delete_all_returning"}:
                color = ACCENT
            tokens.append((word, color))
            i = j
        else:
            tokens.append((ch, DIM))
            i += 1
    return tokens


def tokenize_sql(line: str):
    tokens, i, n = [], 0, len(line)
    while i < n:
        ch = line[i]
        if ch in " \t":
            j = i
            while j < n and line[j] in " \t":
                j += 1
            tokens.append((line[i:j], None))
            i = j
        elif ch.isdigit():
            j = i
            while j < n and line[j].isdigit():
                j += 1
            tokens.append((line[i:j], NUM))
            i = j
        elif ch.isalnum() or ch == "_":
            j = i
            while j < n and (line[j].isalnum() or line[j] in "_."):
                j += 1
            word = line[i:j]
            upper = word.upper()
            color = ACCENT if upper == "RETURNING" else (SQL_KW if upper in SQL_KEYWORDS else TEXT)
            tokens.append((word, color))
            i = j
        else:
            tokens.append((ch, DIM))
            i += 1
    return tokens


def draw_code(draw, x, baseline, tokens, font_, alpha=1.0):
    cursor = px(x)
    for text, color in tokens:
        fill = TEXT if color is None else color
        if alpha < 1.0:
            fill = mix(CARD, fill, alpha)
        draw.text((cursor, px(baseline)), text, font=font_, fill=fill, anchor="ls")
        cursor += draw.textlength(text, font=font_)
    return cursor / DRAW


def chip(draw, x, cy, label, tone, font_=FONT_CODE):
    w = code_w(draw, label, font_) + 22
    h = 26
    rounded(draw, (x, cy - h / 2, x + w, cy + h / 2), 7, mix(CARD, tone, 0.14), tone, 1.1)
    draw.text((px(x + w / 2), px(cy)), label, font=font_, fill=tone, anchor="mm")
    return x + w


def shadow(base: Image.Image):
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box(WIN[0] + 2, WIN[1] + 6, WIN[2] + 6, WIN[3] + 10), radius=px(16), fill=115)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=px(8)))
    return Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), base, mask)


def draw_frame(*, before_chars: int, show_count: bool, after_chars: int, rows_shown: int, sql_alpha: float):
    img = shadow(Image.new("RGB", (W, H), BG))
    draw = ImageDraw.Draw(img)
    rounded(draw, WIN, 16, CARD, BORDER, 1.2)

    t_left(draw, CONTENT, TITLE_CY, "activerecord-returning", FONT_TITLE, TEXT)
    t_left(
        draw,
        CONTENT + ink_w("activerecord-returning", FONT_TITLE) + 14,
        TITLE_CY + 1,
        "UPDATE … RETURNING for ActiveRecord",
        FONT_SM,
        DIM,
    )
    t_left(draw, CONTENT, SUB_CY, "Which rows did that bulk update actually touch?", FONT_UI, MUTED)

    # Panel 1 — what Rails gives you.
    rounded(draw, PANEL_1, 11, CARD_DIM, HAIR, 1.1)
    p1x, p1y = PANEL_1[0] + 22, PANEL_1[1] + 22
    t_left(draw, p1x, p1y, "Rails", FONT_SM, DIM)
    line_y = p1y + 34
    end = draw_code(draw, p1x, line_y, tokenize_ruby(BEFORE[:before_chars]), FONT_CODE)
    if before_chars < len(BEFORE):
        draw.rectangle((px(end + 2), px(line_y - 11), px(end + 4), px(line_y + 3)), fill=ACCENT)
    if show_count:
        cx = chip(draw, p1x, line_y + 30, "=> 2", AMBER)
        t_left(draw, cx + 12, line_y + 30, "how many. not which.", FONT_SM, DIM)

    # Panel 2 — what the gem gives you.
    active = after_chars > 0
    rounded(draw, PANEL_2, 11, CARD_DIM, ACCENT_SOFT if active else HAIR, 1.1)
    p2x, p2y = PANEL_2[0] + 22, PANEL_2[1] + 22
    t_left(draw, p2x, p2y, "activerecord-returning", FONT_SM, ACCENT if active else DIM)

    typed = (AFTER_1 + "\n" + AFTER_2)[:after_chars]
    for i, line in enumerate(typed.split("\n")):
        by = p2y + 35 + i * 22
        end = draw_code(draw, p2x, by, tokenize_ruby(line), FONT_CODE)
        if after_chars < len(AFTER_1) + len(AFTER_2) + 1 and i == len(typed.split("\n")) - 1:
            draw.rectangle((px(end + 2), px(by - 11), px(end + 4), px(by + 3)), fill=ACCENT)

    if rows_shown:
        tx = p2x
        ty = p2y + 92
        col2 = tx + 74
        t_left(draw, tx, ty, TABLE_HEAD[0], FONT_SM, DIM)
        t_left(draw, col2, ty, TABLE_HEAD[1], FONT_SM, DIM)
        rule_right = PANEL_2[2] - 22
        if rows_shown >= len(TABLE_ROWS):
            rule_right -= ink_w("ActiveRecord::Result", FONT_SM) + 14
        draw.line([px(tx), px(ty + 13), px(rule_right), px(ty + 13)], fill=HAIR, width=px(1))
        for i, (id_, email) in enumerate(TABLE_ROWS[:rows_shown]):
            ry = ty + 32 + i * 27
            draw.text((px(tx), px(ry)), id_, font=FONT_NUM, fill=NUM, anchor="lm")
            draw.text((px(col2), px(ry)), f'"{email}"', font=FONT_NUM, fill=STR, anchor="lm")
        if rows_shown >= len(TABLE_ROWS):
            t_left(draw, PANEL_2[2] - 22 - ink_w("ActiveRecord::Result", FONT_SM), ty, "ActiveRecord::Result", FONT_SM, GREEN)

    # SQL strip — one statement, spelled out.
    if sql_alpha > 0.01:
        draw.line(
            [px(CONTENT), px(SQL_TOP - 6), px(CONTENT_R), px(SQL_TOP - 6)],
            fill=mix(CARD, HAIR, sql_alpha),
            width=px(1),
        )
        for i, line in enumerate(SQL):
            by = SQL_TOP + 24 + i * 20
            draw_code(draw, CONTENT, by, tokenize_sql(line), FONT_CODE_SM, alpha=sql_alpha)
        note = "one statement  ·  no second query, no lock, no race  ·  PostgreSQL, SQLite 3.35+"
        t_left(draw, CONTENT, SQL_TOP + 94, note, FONT_SM, mix(CARD, MUTED, sql_alpha))

    return img


def downsample(im: Image.Image) -> Image.Image:
    return im.resize(OUT_SIZE, Image.Resampling.LANCZOS)


def add(frames, durations, img, ms):
    frames.append(img)
    durations.append(int(ms))


def main():
    frames: list[Image.Image] = []
    durations: list[int] = []
    state = dict(before_chars=0, show_count=False, after_chars=0, rows_shown=0, sql_alpha=0.0)

    add(frames, durations, draw_frame(**state), 700)

    # 1. type the Rails call, then the count lands
    for n in range(4, len(BEFORE) + 1, 4):
        state["before_chars"] = n
        add(frames, durations, draw_frame(**state), 45)
    state["before_chars"] = len(BEFORE)
    add(frames, durations, draw_frame(**state), 260)
    state["show_count"] = True
    add(frames, durations, draw_frame(**state), 1500)

    # 2. type the gem's call, then the rows arrive
    total_after = len(AFTER_1) + len(AFTER_2) + 1
    for n in range(4, total_after + 1, 4):
        state["after_chars"] = n
        add(frames, durations, draw_frame(**state), 42)
    state["after_chars"] = total_after
    add(frames, durations, draw_frame(**state), 240)
    for n in range(1, len(TABLE_ROWS) + 1):
        state["rows_shown"] = n
        add(frames, durations, draw_frame(**state), 260)
    add(frames, durations, draw_frame(**state), 1200)

    # 3. the statement behind it
    for t in (0.25, 0.5, 0.75, 1.0):
        state["sql_alpha"] = t
        add(frames, durations, draw_frame(**state), 60)
    add(frames, durations, draw_frame(**state), 3200)

    small = [downsample(im) for im in frames]
    palette_src = small[-1].quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    converted = [im.quantize(palette=palette_src, dither=Image.Dither.NONE) for im in small]
    converted[0].save(
        OUT_GIF,
        save_all=True,
        append_images=converted[1:],
        duration=durations,
        loop=0,
        optimize=False,
        disposal=2,
    )

    gifsicle = Path("/opt/homebrew/bin/gifsicle")
    if gifsicle.exists():
        subprocess.check_call([str(gifsicle), "-O3", "--no-warnings", str(OUT_GIF), "-o", str(OUT_GIF)])

    qa = Path("/tmp/arreturning-demo-qa")
    qa.mkdir(exist_ok=True)
    downsample(draw_frame(before_chars=len(BEFORE), show_count=True, after_chars=0, rows_shown=0, sql_alpha=0.0)).save(qa / "1-count.png")
    downsample(draw_frame(**state)).save(qa / "2-final.png")

    print(f"wrote {OUT_GIF}  {len(frames)} frames  {OUT_SIZE[0]}x{OUT_SIZE[1]}  {OUT_GIF.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()
