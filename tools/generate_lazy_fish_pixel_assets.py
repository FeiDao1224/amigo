from __future__ import annotations

import json
import math
import shutil
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path("/Users/nayoag/TEST/lingzai-mac")
SRC = ROOT / "pet-raw" / "lazy_fish_white.png"
PET_DIR = ROOT / "Sources/Lingzai/Resources/Pets/lazy_fish"
QA_DIR = ROOT / "pet-animation-prototype"

LOW_CANVAS = (80, 96)
SCALE = 2
FINAL_CANVAS = (LOW_CANVAS[0] * SCALE, LOW_CANVAS[1] * SCALE)

PALETTE = [
    (0, 0, 0),
    (37, 31, 44),
    (74, 59, 105),
    (105, 92, 148),
    (238, 207, 49),
    (249, 225, 88),
    (236, 239, 139),
    (161, 153, 47),
    (88, 153, 178),
    (121, 188, 211),
    (171, 222, 229),
    (244, 244, 237),
    (116, 71, 45),
    (205, 129, 54),
    (84, 164, 82),
    (224, 76, 66),
]


ACTION_SPEC = {
    "idle_stand": ("Idle stand", 6, 5, True, True, False),
    "desk_work": ("Desk work", 8, 6, True, True, False),
    "drink_coffee": ("Drink coffee", 6, 6, False, False, False),
    "eat_burger": ("Eat burger", 6, 6, False, False, False),
    "play_phone": ("Play phone", 8, 5, True, True, False),
    "walk": ("Walk", 8, 8, True, True, False),
    "lie_down": ("Lie down", 6, 5, False, True, True),
    "sleep": ("Sleep", 8, 4, True, True, False),
    "wave": ("Wave", 6, 7, False, False, False),
    "shocked": ("Shocked", 4, 8, False, False, False),
}


def flood_remove_white(path: Path) -> Image.Image:
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    px = img.load()
    seen = set()
    q = deque()

    def is_bg(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        if a == 0:
            return True
        return r > 226 and g > 226 and b > 226 and max(r, g, b) - min(r, g, b) < 34

    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))

    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or (x, y) in seen:
            continue
        seen.add((x, y))
        if not is_bg(x, y):
            continue
        px[x, y] = (255, 255, 255, 0)
        q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))

    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def nearest_palette(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    r, g, b = rgb
    return min(PALETTE, key=lambda p: (p[0] - r) ** 2 + (p[1] - g) ** 2 + (p[2] - b) ** 2)


def quantize_hard(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a < 96:
                px[x, y] = (0, 0, 0, 0)
            else:
                nr, ng, nb = nearest_palette((r, g, b))
                px[x, y] = (nr, ng, nb, 255)
    return img


def build_base_sprites() -> dict[str, Image.Image]:
    cut = flood_remove_white(SRC)
    ratio = 82 / cut.height
    low = cut.resize((max(1, int(cut.width * ratio)), 82), Image.Resampling.BOX)
    low = quantize_hard(low)
    small = low.resize((max(1, int(low.width * 0.88)), 72), Image.Resampling.NEAREST)
    tiny = low.resize((max(1, int(low.width * 0.72)), 58), Image.Resampling.NEAREST)
    lying = tiny.rotate(90, resample=Image.Resampling.NEAREST, expand=True)
    return {"stand": low, "small": small, "tiny": tiny, "lying": lying}


def paste_center(canvas: Image.Image, sprite: Image.Image, cx: int, cy: int) -> None:
    canvas.alpha_composite(sprite, (round(cx - sprite.width / 2), round(cy - sprite.height / 2)))


def draw_desk(draw: ImageDraw.ImageDraw) -> None:
    draw.rectangle((8, 67, 72, 72), fill=(116, 71, 45), outline=(0, 0, 0))
    draw.rectangle((13, 72, 17, 95), fill=(74, 59, 44), outline=(0, 0, 0))
    draw.rectangle((63, 72, 67, 95), fill=(74, 59, 44), outline=(0, 0, 0))


def draw_laptop(draw: ImageDraw.ImageDraw, x: int, y: int) -> None:
    draw.rectangle((x, y, x + 24, y + 17), fill=(37, 31, 44), outline=(0, 0, 0))
    draw.rectangle((x + 3, y + 3, x + 21, y + 14), fill=(121, 188, 211))
    draw.rectangle((x - 4, y + 18, x + 28, y + 21), fill=(74, 59, 105), outline=(0, 0, 0))


def draw_cup(draw: ImageDraw.ImageDraw, x: int, y: int, steam: int) -> None:
    draw.rectangle((x, y, x + 9, y + 11), fill=(244, 244, 237), outline=(0, 0, 0))
    draw.rectangle((x + 2, y + 3, x + 7, y + 5), fill=(116, 71, 45))
    draw.arc((x + 6, y + 3, x + 15, y + 10), -80, 95, fill=(0, 0, 0), width=1)
    if steam % 2 == 0:
        draw.point((x + 3, y - 3), fill=(121, 188, 211))
        draw.point((x + 6, y - 5), fill=(121, 188, 211))


def draw_burger(draw: ImageDraw.ImageDraw, x: int, y: int) -> None:
    draw.rectangle((x + 1, y + 3, x + 16, y + 6), fill=(205, 129, 54), outline=(0, 0, 0))
    draw.rectangle((x, y + 7, x + 17, y + 10), fill=(74, 59, 44), outline=(0, 0, 0))
    draw.line((x + 1, y + 11, x + 16, y + 11), fill=(84, 164, 82), width=2)
    draw.rectangle((x + 1, y + 13, x + 16, y + 16), fill=(249, 225, 88), outline=(0, 0, 0))


def draw_phone(draw: ImageDraw.ImageDraw, x: int, y: int) -> None:
    draw.rectangle((x, y, x + 10, y + 18), fill=(37, 31, 44), outline=(0, 0, 0))
    draw.rectangle((x + 2, y + 2, x + 8, y + 15), fill=(121, 188, 211))


def draw_bed(draw: ImageDraw.ImageDraw) -> None:
    draw.rectangle((14, 69, 72, 83), fill=(121, 188, 211), outline=(0, 0, 0))
    draw.rectangle((7, 59, 25, 76), fill=(236, 239, 139), outline=(0, 0, 0))


def draw_z(draw: ImageDraw.ImageDraw, t: int) -> None:
    if t % 2 == 0:
        draw.line((58, 28, 63, 28, 58, 34, 63, 34), fill=(105, 92, 148), width=1)
        draw.line((66, 20, 70, 20, 66, 25, 70, 25), fill=(105, 92, 148), width=1)


def make_frame(action: str, t: int, count: int, sprites: dict[str, Image.Image]) -> Image.Image:
    c = Image.new("RGBA", LOW_CANVAS, (0, 0, 0, 0))
    d = ImageDraw.Draw(c, "RGBA")
    phase = math.sin((t / count) * math.tau)

    if action == "idle_stand":
        s = sprites["stand"]
        paste_center(c, s, 40, 53 + round(phase))
    elif action == "desk_work":
        s = sprites["small"]
        paste_center(c, s, 39, 49 + round(phase))
        draw_desk(d)
        draw_laptop(d, 28, 52)
    elif action == "drink_coffee":
        s = sprites["stand"]
        paste_center(c, s, 43, 53 + (t % 2))
        draw_cup(d, 18, 43 - (1 if t in (2, 3) else 0), t)
    elif action == "eat_burger":
        s = sprites["stand"]
        paste_center(c, s, 43, 53)
        draw_burger(d, 15, 45 + (t % 2))
    elif action == "play_phone":
        s = sprites["stand"]
        paste_center(c, s, 38, 53 + round(phase))
        draw_phone(d, 60, 42 + (t % 2))
    elif action == "walk":
        s = sprites["stand"]
        x = 33 + (t % 4) * 3
        paste_center(c, s, x, 53 + (t % 2) * 2)
    elif action == "lie_down":
        draw_bed(d)
        paste_center(c, sprites["lying"], 44, 61 + (1 if t > 2 else 0))
    elif action == "sleep":
        draw_bed(d)
        paste_center(c, sprites["lying"], 44, 61 + (t % 2))
        draw_z(d, t)
    elif action == "wave":
        s = sprites["stand"]
        paste_center(c, s, 40, 53 + (t % 2))
        if t % 2 == 0:
            d.line((17, 30, 13, 26), fill=(0, 0, 0), width=1)
            d.line((19, 29, 20, 24), fill=(0, 0, 0), width=1)
    elif action == "shocked":
        s = sprites["stand"]
        paste_center(c, s, 40 + (-2 if t % 2 == 0 else 2), 52)
        d.rectangle((55, 21, 60, 27), fill=(224, 76, 66), outline=(0, 0, 0))

    return c.resize(FINAL_CANVAS, Image.Resampling.NEAREST)


def save_contact_sheet(first_frames: list[tuple[str, Image.Image]]) -> None:
    cols = 5
    cell = (190, 230)
    rows = math.ceil(len(first_frames) / cols)
    sheet = Image.new("RGBA", (cols * cell[0], rows * cell[1]), (18, 18, 20, 255))
    d = ImageDraw.Draw(sheet)
    for i, (label, frame) in enumerate(first_frames):
        x = (i % cols) * cell[0]
        y = (i // cols) * cell[1]
        d.rectangle((x + 10, y + 10, x + cell[0] - 10, y + cell[1] - 34), fill=(38, 39, 43), outline=(88, 91, 99))
        sheet.alpha_composite(frame, (x + 15, y + 16))
        d.text((x + 13, y + cell[1] - 26), label, fill=(238, 238, 232))
    QA_DIR.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(QA_DIR / "pixel16_contact_sheet.png")


def main() -> None:
    if PET_DIR.exists():
        shutil.rmtree(PET_DIR)
    PET_DIR.mkdir(parents=True)

    sprites = build_base_sprites()
    animations = {}
    first_frames = []

    for action, (label, frame_count, fps, loop, interruptible, hold_last) in ACTION_SPEC.items():
        action_dir = PET_DIR / action
        action_dir.mkdir(parents=True)
        for i in range(frame_count):
            frame = make_frame(action, i, frame_count, sprites)
            frame.save(action_dir / f"frame_{i:03d}.png")
            if i == 0:
                first_frames.append((label, frame))
        animations[action] = {
            "fps": fps,
            "loop": loop,
            "interruptible": interruptible,
            "holdLastFrame": hold_last,
            "frameCount": frame_count,
        }

    profile = {
        "petId": "lazy_fish",
        "displayName": "摆摆鱼",
        "defaultAction": "idle_stand",
        "pixelCanvasWidth": FINAL_CANVAS[0],
        "pixelCanvasHeight": FINAL_CANVAS[1],
        "scale": 1,
        "animations": animations,
    }
    (PET_DIR / "profile.json").write_text(json.dumps(profile, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    save_contact_sheet(first_frames)


if __name__ == "__main__":
    main()
