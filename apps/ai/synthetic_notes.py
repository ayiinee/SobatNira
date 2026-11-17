"""Render reproducible synthetic notes for local smoke tests."""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def font(size):
    for name in ("arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def generate(folder):
    folder.mkdir(parents=True, exist_ok=True)
    for name, weight in (("truck", "1250"), ("ambiguous", "1250 / 1280")):
        note = Image.new("RGB", (1160, 650), "white")
        draw = ImageDraw.Draw(note)
        for index, line in enumerate(("TANGGAL: 16-11-2026", "PENGIRIM: PEMASOK DEMO", "NO. KENDARAAN: TEST-001",
                                      "BRIX: 12,5", f"BERAT BERSIH: {weight} KG", "JENIS TEBU: BL", "OPERATOR: PETUGAS DEMO")):
            draw.text((55, 35 + index * 78), line, fill="black", font=font(43))
        note.save(folder / f"{name}.png")
    for name, weight in (("production", "25"), ("update", "26")):
        note = Image.new("RGB", (1830, 460), "white")
        draw = ImageDraw.Draw(note)
        for index, line in enumerate(("TGL: 16-11-2026", "SIF: A", "CHEF: DEMO")):
            draw.text((20, 15 + index * 45), line, fill="black", font=font(32))
        rows = (("TEBU", "WAJAN", "BRIX", "ISI", "GAMPING", "JAM TURUN", "GRADE", "HASIL"),
                ("DEMO-A", "1", "15", "115", "1 1/2", "15:35", "A", weight),
                ("DEMO-B", "1", "12", "110", "1", "16:35", "B", "22"))
        for y, row in enumerate(rows):
            for x, value in enumerate(row):
                draw.text((20 + x * 215, 170 + y * 65), value, fill="black", font=font(32))
        note.save(folder / f"{name}.png")
    cooking = Image.new("RGB", (1280, 430), "white")
    draw = ImageDraw.Draw(cooking)
    header_font, data_font = font(54), font(39)
    header = "WAJAN ISI GAMPING"
    draw.text((28, 25), "TGL: 26-09-2026", font=data_font, fill="black")
    draw.text((28, 140), "TEBU", font=header_font, fill="black")
    draw.text((350, 140), header, font=header_font, fill="black")
    for heading, value in (("WAJAN", "2"), ("ISI", "115"), ("GAMPING", "1 1/2")):
        start = header.index(heading)
        center = 350 + header_font.getlength(header[:start]) + header_font.getlength(heading) / 2
        draw.text((center, 300), value, anchor="mm", font=data_font, fill="black")
    draw.text((35, 275), "DEMO-A", font=data_font, fill="black")
    cooking.save(folder / "cooking.png")
    Image.new("RGB", (640, 420), "white").save(folder / "unreadable.png")
    manual = Image.new("RGB", (640, 420), "white")
    ImageDraw.Draw(manual).text((45, 60), "CATATAN TIMBANG\n16-11-2026\nPEMASOK DEMO\nBL\n1250 KG", fill="black", font=font(39))
    manual.save(folder / "manual.png")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    generate(parser.parse_args().directory)
