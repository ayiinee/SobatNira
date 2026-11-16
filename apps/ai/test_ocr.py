from io import BytesIO
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient
from PIL import Image

from benchmark_ocr import evaluate, load_cases
from main import app
from ocr_parser import Token, extract
from ocr_service import SCHEMAS


def token(text, x, y):
    return Token(text, 0.93, (x, y, 0.07, 0.02))


class OcrTest(TestCase):
    def setUp(self):
        self.request = {name: str(uuid4()) for name in ("request_id", "document_id", "submission_id", "revision_id", "factory_id")}
        self.request.update(schema_version="1.0.0", image={
            "asset_id": str(uuid4()), "object_key": "a" * 64, "mime_type": "image/png",
        })
        buffer = BytesIO()
        Image.new("RGB", (200, 180), "white").save(buffer, "PNG")
        self.image = buffer.getvalue()
        self.client = TestClient(app)
        self.headers = {"X-Internal-Service-Token": "synthetic-ocr-token"}

    def post(self):
        return self.client.post("/internal/v1/ocr/extract", json=self.request, headers=self.headers)

    def test_examples_conform_to_note_schemas(self):
        directory = Path(__file__).resolve().parents[2] / "docs" / "ai" / "examples"
        for file, schema in [("truck-arrival-note", "truck-arrival-note"), ("production-note-progressive-update", "production-note")]:
            with self.subTest(file=file):
                SCHEMAS[schema].validate(json.loads((directory / f"{file}.example.json").read_text(encoding="utf-8")))

    def test_serves_truck_with_evidence_and_preserves_provider_disagreement(self):
        tokens = [token(text, 0.1, 0.05 + index * 0.08) for index, text in enumerate([
            "TANGGAL: 16-11-2026", "PENGIRIM: PEMASOK DEMO", "NO. KENDARAAN: TEST-001",
            "BRIX: 12,5", "BERAT BERSIH: 1.250", "JENIS TEBU: BL", "OPERATOR: PETUGAS DEMO",
        ])]
        env = {"AI_SERVICE_INTERNAL_TOKEN": self.headers["X-Internal-Service-Token"],
               "GEMINI_API_KEY": "test-key", "GEMINI_VISION_MODEL": "test-model"}
        with (patch.dict("os.environ", env), patch("ocr_service.load_media", return_value=self.image),
              patch("ocr_service.recognize", return_value=tokens), patch("ocr_service.reread", return_value="1251") as reread):
            response = self.post()
        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        self.assertEqual(data["status"], "PARTIAL")
        SCHEMAS["extraction-envelope"].validate(data)
        self.assertEqual(len(data["processing"]["raw_ocr"]), len(tokens))
        weight = data["extraction"]["header"]["net_weight_kg"]
        self.assertEqual(weight["raw_value"], "1.250")
        self.assertIsNone(weight["normalized_value"])
        self.assertEqual(weight["status"], "AMBIGUOUS")
        self.assertEqual(weight["unit"], "kg")
        self.assertEqual(weight["evidence"][0]["asset_id"], self.request["image"]["asset_id"])
        self.assertEqual([item["value"] for item in weight["alternatives"]], ["1.250", "1251"])
        self.assertEqual(data["extraction"]["header"]["brix"]["normalized_value"], 12.5)
        self.assertIsNone(data["extraction"]["header"]["brix"]["unit"])
        reread.assert_called_once()

    def test_production_preserves_reused_pan_unmapped_columns_and_units(self):
        tokens = [token("TGL: 16-11-2026", 0.03, 0.04), token("SIF: A", 0.2, 0.04)]
        for y, row in [(0.2, ["TEBU", "WAJAN", "BRIX", "ISI", "GAMPING", "?", "JAM TURUN", "GRADE", "HASIL"]),
                       (0.3, ["DEMO-A", "1", "15", "115", "1 1/2", "RAW", "15:35", "A", "25"]),
                       (0.4, ["DEMO-B", "1", None, "100", "2", None, "16:35", None, None])]:
            tokens.extend(token(text, 0.02 + index * 0.1, y) for index, text in enumerate(row) if text)
        note = extract(tokens, self.request["image"]["asset_id"], "1.0.0", "1.0.0")
        SCHEMAS["production-note"].validate(note)
        self.assertEqual(len(note["cane_blocks"]), 2)
        first, second = [block["batches"][0] for block in note["cane_blocks"]]
        self.assertEqual(first["pan_number"]["normalized_value"], second["pan_number"]["normalized_value"])
        self.assertEqual(second["brix_measurement_stage"], "UNKNOWN")
        self.assertEqual(first["cooking"]["gamping"]["unit"], "CUSTOM_MEASURE")
        self.assertEqual(first["cooking"]["gamping"]["normalized_value"], "1 1/2")
        self.assertEqual(first["cooking"]["isi_kg"]["unit"], "kg")
        self.assertIsNone(second["output"]["hasil_kg"]["normalized_value"])
        self.assertEqual(note["unmapped_columns"][0]["header_raw"], "?")

    def test_invalid_image_and_unknown_layout_are_safe_results(self):
        env = {"AI_SERVICE_INTERNAL_TOKEN": self.headers["X-Internal-Service-Token"]}
        with patch.dict("os.environ", env), patch("ocr_service.load_media", return_value=b"not-an-image"):
            response = self.post()
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(response.json()["status"], "FAILED")
            self.assertIsNone(response.json()["extraction"])
        with (patch.dict("os.environ", env), patch("ocr_service.load_media", return_value=self.image),
              patch("ocr_service.recognize", return_value=[])):
            response = self.post()
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(response.json()["status"], "NEEDS_REVIEW")
            self.assertEqual(response.json()["document_type"], "UNKNOWN")

    def test_service_auth_rejects_access(self):
        with patch.dict("os.environ", {"AI_SERVICE_INTERNAL_TOKEN": "test-token"}):
            self.assertEqual(self.post().status_code, 401)

    def test_benchmark_scores_normalized_values_and_missing_fields(self):
        with TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "synthetic.png").write_bytes(self.image)
            manifest = root / "ground-truth.json"
            manifest.write_text(json.dumps([{"image": "synthetic.png", "document_type": "TRUCK_ARRIVAL_NOTE", "fields": {
                "header.net_weight_kg": {"normalized_value": 1250, "unit": "kg"},
                "header.supplier_name": {"normalized_value": "Pemasok Berbeda"},
                "header.unknown": {"status": "READ"},
            }}]), encoding="utf-8")
            tokens = [token(line, .1, .1 + index * .1) for index, line in enumerate([
                "TANGGAL: 16-11-2026", "PENGIRIM: PEMASOK DEMO", "NO. KENDARAAN: TEST-001", "BERAT BERSIH: 1250",
            ])]
            report = evaluate(list(load_cases(manifest)), lambda *_: tokens)
        self.assertEqual(report["classification"], {"TRUCK_ARRIVAL_NOTE": {"TRUCK_ARRIVAL_NOTE": 1}})
        self.assertEqual(report["fields"]["TRUCK_ARRIVAL_NOTE.header.net_weight_kg"]["correct"], 1)
        self.assertEqual(report["fields"]["TRUCK_ARRIVAL_NOTE.header.supplier_name"]["incorrect"], 1)
        self.assertEqual(report["fields"]["TRUCK_ARRIVAL_NOTE.header.unknown"]["missing"], 1)
