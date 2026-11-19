"""Evaluate PaddleOCR against an offline, annotated image set."""

import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
from statistics import median
from time import monotonic

from ocr_parser import extract, extracted_fields
from ocr_service import MAX_BYTES, decode_image, recognize, warm_paddle


DOCUMENT_TYPES = {"TRUCK_ARRIVAL_NOTE", "PRODUCTION_NOTE", "UNKNOWN"}
MIME_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}
GROUND_TRUTH_KEYS = {"status", "raw_value", "normalized_value", "unit"}
CRITICAL_FIELDS = {"net_weight_kg", "hasil_kg"}
THRESHOLDS = (0.80, 0.85, 0.90, 0.95)


def load_cases(manifest):
    cases = json.loads(manifest.read_text(encoding="utf-8-sig"))
    if not isinstance(cases, list) or not cases:
        raise ValueError("Ground truth harus berupa array berisi minimal satu nota")
    root = manifest.resolve().parent
    for index, case in enumerate(cases, 1):
        if (not isinstance(case, dict) or not isinstance(case.get("image"), str)
                or not isinstance(case.get("document_type"), str) or case["document_type"] not in DOCUMENT_TYPES):
            raise ValueError(f"Metadata kasus {index} tidak valid")
        image = (root / case["image"]).resolve()
        mime = MIME_TYPES.get(image.suffix.lower())
        if not image.is_relative_to(root) or not mime or not image.is_file() or image.stat().st_size > MAX_BYTES:
            raise ValueError(f"Foto kasus {index} tidak valid atau berada di luar direktori ground truth")
        fields = case.get("fields", {})
        if not isinstance(fields, dict) or any(
            not path or not isinstance(expected, dict) or not expected or not expected.keys() <= GROUND_TRUTH_KEYS
            for path, expected in fields.items()
        ):
            raise ValueError(f"Anotasi field kasus {index} tidak valid")
        yield image, mime, case["document_type"], fields


def evaluate(cases, infer):
    classes = defaultdict(Counter)
    metrics = defaultdict(Counter)
    confidence = defaultdict(list)
    latencies = []
    for index, (image, mime, expected_type, annotations) in enumerate(cases, 1):
        start = monotonic()
        try:
            image_data = decode_image(image.read_bytes(), mime)
            note = extract(infer(image_data, True), f"benchmark-{index}", "1.0.0", "1.0.0")
        except (OSError, ValueError) as error:
            raise ValueError(f"Gagal membaca kasus {index}") from error
        latencies.append((monotonic() - start) * 1000)
        predicted = note["document_type"] if note else "UNKNOWN"
        classes[expected_type][predicted] += 1
        actual = dict(extracted_fields(note))
        for path, expected in annotations.items():
            metric = f"{expected_type}.{path}"
            tally = metrics[metric]
            tally["total"] += 1
            found = actual.get(path) if expected_type == predicted else None
            if found is None:
                tally["missing"] += 1
            elif all(key in found and found[key] == value for key, value in expected.items()):
                tally["correct"] += 1
            else:
                tally["incorrect"] += 1
            if found and found["status"] == "READ":
                tally["read"] += 1
                wrong_read = any(key in expected and found[key] != expected[key]
                                 for key in ("normalized_value", "unit", "status"))
                tally["wrong_read"] += int(wrong_read)
                if path.rsplit(".", 1)[-1] in CRITICAL_FIELDS:
                    confidence[metric].append((found["confidence"], wrong_read))
    calibration = {}
    for metric, observations in confidence.items():
        thresholds = {}
        for threshold in THRESHOLDS:
            kept = [wrong for score, wrong in observations if score is not None and score >= threshold]
            thresholds[str(threshold)] = {"read_kept": len(kept), "wrong_read_kept": sum(kept)}
        calibration[metric] = {
            "read_without_confidence": sum(score is None for score, _ in observations),
            "thresholds": thresholds,
        }
    latencies.sort()
    return {"images": len(latencies), "classification": dict(classes), "fields": dict(metrics),
            "median_processing_ms": round(median(latencies), 1),
            "p95_processing_ms": round(latencies[math.ceil(len(latencies) * .95) - 1], 1),
            "critical_read_calibration": calibration}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    cases = list(load_cases(args.manifest))
    warm_paddle()
    print(json.dumps(evaluate(cases, recognize), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
