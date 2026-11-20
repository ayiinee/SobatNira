"""Verify and normalize the synthetic Rekap downloaded from Flutter."""
from contextlib import closing
from pathlib import Path
import sys

from pypdfium2 import PdfDocument


def extract(path: Path):
    with PdfDocument(path) as pdf:
        pages = []
        for page in pdf:
            with closing(page), closing(page.get_textpage()) as text:
                pages.append(" ".join(text.get_text_range().split()))
    return "\n".join(pages)


def main(folder: Path):
    content = extract(folder / "rekap.pdf")
    for expected in ("OCR-A-UJI", "OCR-B-UJI", "SMOKE-UJI", "25 kg", "375.000"):
        if expected not in content:
            raise ValueError(f"PDF Rekap tidak memuat {expected}")
    (folder / "rekap.txt").write_text(content + "\n", encoding="utf-8")
    owner = extract(folder / "owner-rekap.pdf")
    for expected in ("OCR-A-UJI", "Gula final (kg) | 25", "Margin produksi (Rp) | 375000"):
        if expected not in owner:
            raise ValueError(f"PDF owner tidak memuat {expected}")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
