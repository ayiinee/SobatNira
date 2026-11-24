"""Native inference smoke using a generated image; no partner data."""
from PIL import Image, ImageDraw
from ocr_service import recognize, PADDLE_WORKER


if __name__ == "__main__":
    image = Image.new("RGB", (600, 150), "white")
    ImageDraw.Draw(image).text((20, 40), "SOBATNIRA 12345", fill="black", font_size=40)
    try:
        tokens = recognize(image, False)
        assert tokens, "Native OCR produced no tokens for synthetic text"
        assert any("12345" in token.text.replace(" ", "") for token in tokens), tokens
    finally:
        PADDLE_WORKER.close()
