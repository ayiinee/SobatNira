from io import BytesIO
import base64
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient
import httpx
from PIL import Image

from benchmark_ocr import evaluate, load_cases
from main import app
from ocr_parser import Token, extract
from ocr_service import SCHEMAS, validate_runtime


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
        url = "https://generativelanguage.googleapis.com/v1beta/models/test-model:generateContent"
        result = httpx.Response(200, json={"candidates": [{"content": {"parts": [{"text": '{"value":"1251"}'}]}}]},
                                request=httpx.Request("POST", url))
        with (patch.dict("os.environ", env), patch("ocr_service.load_media", return_value=self.image),
              patch("ocr_service.recognize", return_value=tokens), patch("ocr_service.httpx.post", return_value=result) as reread):
            response = self.post()
            reread.assert_called_once()
            self.assertEqual(reread.call_args.args[0], url)
            self.assertEqual(reread.call_args.kwargs["headers"], {"x-goog-api-key": "test-key"})
            parts = reread.call_args.kwargs["json"]["contents"][0]["parts"]
            with Image.open(BytesIO(base64.b64decode(parts[1]["inlineData"]["data"]))) as crop:
                self.assertLess(crop.width * crop.height, 200 * 180)
            reread.return_value = httpx.Response(429, request=httpx.Request("POST", url))
            limited = self.post()
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
        self.assertEqual(limited.status_code, 200)
        rate_limited = limited.json()
        self.assertEqual(rate_limited["extraction"]["header"]["net_weight_kg"]["raw_value"], "1.250")
        self.assertEqual(rate_limited["extraction"]["header"]["net_weight_kg"]["status"], "AMBIGUOUS")
        self.assertIn("VISION_UNAVAILABLE", [issue["code"] for issue in rate_limited["issues"]])

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

    def test_cooking_note_splits_joined_headers_without_a_result_column(self):
        for merged in ("WAJAN ISI GAMPING", "WAJANISIGAMPING"):
            with self.subTest(merged=merged):
                tokens = [
                    token("TGL: 26-09-2026", .04, .04),
                    token("TEBU", .02, .2),
                    Token(merged, .95, (.19, .2, .48, .02)),
                    token("?", .7, .2),
                    token("JAM TURUN", .84, .2),
                    token("DEMO-A", .02, .3),
                    token("2", .22, .3),
                    token("115", .38, .3),
                    token("1 1/2", .54, .3),
                    token("RAW", .7, .3),
                    token("15:30", .84, .3),
                ]
                asset = self.request["image"]["asset_id"]
                note = extract(tokens, asset, "1.0.0", "1.0.0")
                SCHEMAS["production-note"].validate(note)
                batch, = note["cane_blocks"][0]["batches"]
                self.assertEqual(note["document_type"], "PRODUCTION_NOTE")
                self.assertEqual(batch["pan_number"]["normalized_value"], "2")
                self.assertEqual(batch["cooking"]["isi_kg"]["normalized_value"], 115)
                self.assertEqual(batch["cooking"]["isi_kg"]["evidence"], [tokens[7].evidence(asset)])
                self.assertEqual(batch["cooking"]["gamping"]["raw_value"], "1 1/2")
                self.assertEqual(batch["cooking"]["gamping"]["unit"], "CUSTOM_MEASURE")
                self.assertEqual(batch["output"]["hasil_kg"]["status"], "NOT_PRESENT")
                self.assertEqual(batch["unmapped_cells"][0]["cell_raw"], "RAW")

    def test_supplier_keeps_all_fragments_and_requests_reread_when_uncertain(self):
        tokens = [
            token("TANGGAL: 26-09-2026", .1, .10),
            token("PENGIRIM:", .1, .20),
            token("CV", .22, .20),
            Token("KEBUN", .81, (.33, .20, .08, .02)),
            token("DEMO", .48, .20),
            token("BRIX: 19", .65, .20),
            token("NO. KENDARAAN: UJI-001", .1, .30),
            token("BERAT BERSIH: 5050", .1, .40),
        ]
        asset = self.request["image"]["asset_id"]
        confident = [tokens[0], token("PENGIRIM CV", .1, .20), token("KEBUN", .33, .20), *tokens[4:]]
        note = extract(confident, asset, "1.0.0", "1.0.0")
        self.assertEqual(note["header"]["supplier_name"]["normalized_value"], "CV KEBUN DEMO")
        self.assertEqual(note["header"]["supplier_name"]["status"], "READ")

        env = {"AI_SERVICE_INTERNAL_TOKEN": self.headers["X-Internal-Service-Token"],
               "GEMINI_API_KEY": "test-key", "GEMINI_VISION_MODEL": "test-model"}
        result = httpx.Response(
            200, json={"candidates": [{"content": {"parts": [{"text": '{"value":"CV KEBON DEMO"}'}]}}]},
            request=httpx.Request("POST", "https://generativelanguage.googleapis.com/v1beta/models/test-model:generateContent"),
        )
        with (patch.dict("os.environ", env), patch("ocr_service.load_media", return_value=self.image),
              patch("ocr_service.recognize", return_value=tokens), patch("ocr_service.httpx.post", return_value=result) as reread):
            response = self.post()
            reread.assert_called_once()
            parts = reread.call_args.kwargs["json"]["contents"][0]["parts"]
            self.assertIn("supplier name", parts[0]["text"])
            with Image.open(BytesIO(base64.b64decode(parts[1]["inlineData"]["data"]))) as crop:
                self.assertIn(crop.width, {66, 67})
        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        self.assertEqual(data["status"], "PARTIAL")
        supplier = data["extraction"]["header"]["supplier_name"]
        self.assertEqual(supplier["raw_value"], "CV KEBUN DEMO")
        self.assertIsNone(supplier["normalized_value"])
        self.assertEqual(supplier["status"], "AMBIGUOUS")
        self.assertEqual(supplier["evidence"], [item.evidence(asset) for item in tokens[2:5]])
        self.assertEqual([alternative["value"] for alternative in supplier["alternatives"]], ["CV KEBUN DEMO", "CV KEBON DEMO"])
        self.assertEqual(data["extraction"]["header"]["brix"]["normalized_value"], 19)

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

    def test_readiness_reports_its_mode_after_authentication(self):
        env = {"AI_SERVICE_INTERNAL_TOKEN": self.headers["X-Internal-Service-Token"], "SOBATNIRA_MODE": "local"}
        path = "/internal/v1/ocr/ready"
        with patch.dict("os.environ", env), patch("ocr_service.paddle_engine") as engine:
            self.assertEqual(self.client.get(path).status_code, 401)
            engine.assert_not_called()
            response = self.client.get(path, headers=self.headers)
            self.assertEqual(response.json(), {"status": "ok", "engine": "PADDLEOCR", "mode": "local"})
            engine.assert_called_once()

    def test_ocr_auth_requires_a_secure_media_origin(self):
        env = {"SOBATNIRA_MODE": "local", "AI_SERVICE_INTERNAL_TOKEN": "x" * 32}
        for url in ("http://api.example.invalid", "https://user:synthetic@api.example.invalid", "http://127.0.0.1?query=synthetic"):
            with self.subTest(url=url), patch.dict("os.environ", {**env, "OCR_MEDIA_BASE_URL": url}, clear=True):
                with self.assertRaisesRegex(RuntimeError, r"^FastAPI: OCR_MEDIA_BASE_URL$"):
                    validate_runtime()
        with patch.dict("os.environ", {**env, "OCR_MEDIA_BASE_URL": "http://127.0.0.1:3000"}, clear=True):
            validate_runtime()

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
