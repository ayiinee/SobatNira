"""Evaluate PaddleOCR against an offline, annotated image set."""

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
import json
import math
from pathlib import Path
from statistics import median
from time import monotonic

from ocr_parser import extracted_fields
from ocr_service import MAX_BYTES, NOTE_SCHEMA_VERSION, NOTE_TEMPLATE_VERSION, decode_image, read_note, warm_paddle


DOCUMENT_TYPES = {"TRUCK_ARRIVAL_NOTE", "PRODUCTION_NOTE", "UNKNOWN"}
MIME_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}
GROUND_TRUTH_KEYS = {"status", "raw_value", "normalized_value", "unit"}
CRITICAL_FIELDS = {"net_weight_kg", "isi_kg", "hasil_kg", "cane_label", "grade"}
UNSCORABLE = {"NOT_PRESENT", "ILLEGIBLE", "AMBIGUOUS"}
SPLITS = {"tuning", "test"}
THRESHOLDS = (0.80, 0.85, 0.90, 0.95)


@dataclass(frozen=True)
class Case:
    image: Path
    mime: str
    document_type: str
    fields: dict
    required_fields: tuple[str, ...]
    document_group: str


def load_cases(manifest, split=None):
    cases = json.loads(manifest.read_text(encoding="utf-8-sig"))
    if not isinstance(cases, list) or not cases:
        raise ValueError("Ground truth harus berupa array berisi minimal satu nota")
    root = manifest.resolve().parent
    groups = {}
    images = {}
    selected = []
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
            or ("status" in expected and expected["status"] not in ("READ", "NOT_PRESENT", "ILLEGIBLE", "AMBIGUOUS"))
            for path, expected in fields.items()
        ):
            raise ValueError(f"Anotasi field kasus {index} tidak valid")
        required = case.get("required_fields", [])
        if not isinstance(required, list) or any(not isinstance(path, str) or path not in fields for path in required):
            raise ValueError(f"Field wajib kasus {index} belum diberi anotasi")
        group = case.get("document_group")
        partition = case.get("split")
        if partition is not None or group is not None or split is not None:
            if not isinstance(group, str) or not group.strip() or not isinstance(partition, str) or partition not in SPLITS:
                raise ValueError(f"Kasus {index} memerlukan document_group dan split tuning/test")
            if groups.setdefault(group, partition) != partition or images.setdefault(image, partition) != partition:
                raise ValueError(f"Foto atau grup nota kasus {index} muncul di lebih dari satu split")
        if split is None or split == partition:
            selected.append(Case(image, mime, case["document_type"], fields, tuple(dict.fromkeys(required)), group or str(image)))
    if split is None and len(set(groups.values())) > 1:
        raise ValueError("Pilih --split tuning atau --split test untuk manifest dengan dua split")
    if not selected:
        raise ValueError("Tidak ada nota pada split yang dipilih")
    return selected


def timing(samples):
    ordered = sorted(duration for duration, _ in samples)
    count = len(ordered)
    groups = len({group for _, group in samples})
    return {"samples": count, "median_ms": round(median(ordered), 1),
            "min_ms": round(ordered[0], 1), "max_ms": round(ordered[-1], 1),
            "document_groups": groups,
            "p95_ms": round(ordered[math.ceil(count * .95) - 1], 1) if groups >= 100 else None}


def evaluate(cases, infer=None):
    classes = defaultdict(Counter)
    metrics = defaultdict(Counter)
    confidence = defaultdict(list)
    latencies = defaultdict(list)
    whole_note = defaultdict(Counter)
    for index, case in enumerate(cases, 1):
        expected_type = case.document_type
        start = monotonic()
        try:
            image = decode_image(case.image.read_bytes(), case.mime)
            _, note = read_note(image, f"benchmark-{index}", NOTE_SCHEMA_VERSION, NOTE_TEMPLATE_VERSION, infer=infer)
        except (OSError, ValueError) as error:
            raise ValueError(f"Gagal membaca kasus {index}") from error
        latencies[expected_type].append(((monotonic() - start) * 1000, case.document_group))
        predicted = note["document_type"] if note else "UNKNOWN"
        classes[expected_type][predicted] += 1
        actual = dict(extracted_fields(note))
        matched = set()
        for path, expected in case.fields.items():
            metric = f"{expected_type}.{path}"
            tally = metrics[metric]
            found = actual.get(path) if expected_type == predicted else None
            if expected.get("status") in UNSCORABLE:
                tally["unscorable"] += 1
                if found and found["status"] == "READ" and found["normalized_value"] is not None:
                    tally["read_without_ground_truth_value"] += 1
                continue
            tally["total"] += 1
            if found is None:
                tally["missing"] += 1
            elif all(key in found and found[key] == value for key, value in expected.items()):
                tally["correct"] += 1
                matched.add(path)
            else:
                tally["incorrect"] += 1
            if found and found["status"] == "READ":
                tally["read"] += 1
                wrong_read = path not in matched
                tally["wrong_read"] += int(wrong_read)
                if path.rsplit(".", 1)[-1] in CRITICAL_FIELDS:
                    confidence[metric].append((found["confidence"], wrong_read))
        if case.required_fields:
            tally = whole_note[expected_type]
            if any(case.fields[path].get("status") in UNSCORABLE for path in case.required_fields):
                tally["unscorable"] += 1
            else:
                tally["total"] += 1
                tally["all_correct"] += int(all(path in matched for path in case.required_fields))
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
    summary = timing([value for samples in latencies.values() for value in samples])
    return {"images": summary["samples"], "classification": dict(classes), "fields": dict(metrics),
            "required_fields_per_note": dict(whole_note),
            "median_processing_ms": summary["median_ms"], "p95_processing_ms": summary["p95_ms"],
            "processing_by_document_type": {kind: timing(samples) for kind, samples in latencies.items()},
            "critical_read_calibration": calibration}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--split", choices=sorted(SPLITS))
    args = parser.parse_args()
    cases = load_cases(args.manifest, args.split)
    warm_paddle()
    print(json.dumps(evaluate(cases), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
