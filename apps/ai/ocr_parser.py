from dataclasses import dataclass
from datetime import date
from math import isfinite
import re
from statistics import median


@dataclass(frozen=True)
class Token:
    text: str
    confidence: float | None
    bbox: tuple[float, float, float, float]

    @property
    def center(self):
        x, y, width, height = self.bbox
        return x + width / 2, y + height / 2

    def evidence(self, asset_id):
        return {"asset_id": asset_id, "coordinate_space": "ORIGINAL_IMAGE_NORMALIZED", "bbox": list(self.bbox)}


TRUCK = {
    "TANGGAL": "arrival_date", "PENGIRIM": "supplier_name", "NO KENDARAAN": "vehicle_number",
    "BRIX": "brix", "BERAT BERSIH": "net_weight_kg", "JENIS TEBU": "cane_type", "OPERATOR": "receiving_operator",
}
PRODUCTION = {"TGL": "production_date", "SIF": "shift", "CHEF": "chef"}
COLUMNS = {
    "TEBU": "cane_label", "WAJAN": "pan_number", "BRIX": "brix", "ISI": "isi_kg", "GAMPING": "gamping",
    "JAM TURUN": "jam_turun", "GRADE": "grade", "HASIL": "hasil_kg",
}
WEIGHTS = {"net_weight_kg", "isi_kg", "hasil_kg"}


def label(text):
    return " ".join(re.sub(r"[^A-Z0-9 ]", " ", text.upper()).split())


def normalized(key, text):
    value = text.strip()
    if key in WEIGHTS or key == "brix":
        value = re.sub(r"\s*kg$", "", value, flags=re.I) if key in WEIGHTS else value
        if re.fullmatch(r"[0-9]{1,3}(?:\.[0-9]{3})+,\d+", value):
            value = value.replace(".", "")
        if not re.fullmatch(r"\d+(?:,\d+|\.\d{1,2})?", value):
            return None
        number = float(value.replace(",", "."))
        return number if isfinite(number) else None
    if key in {"arrival_date", "production_date"}:
        try:
            if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
                return date.fromisoformat(value).isoformat()
            match = re.fullmatch(r"(\d{1,2})[-/](\d{1,2})[-/](\d{4})", value)
            return date(int(match[3]), int(match[2]), int(match[1])).isoformat() if match else None
        except ValueError:
            return None
    if key == "jam_turun":
        match = re.fullmatch(r"([01]?\d|2[0-3])[:.]([0-5]\d)", value)
        return f"{int(match[1]):02}:{match[2]}" if match else None
    return value


def field(key, values, asset_id, missing="NOT_PRESENT"):
    text = " ".join(token.text for token in values) if values else None
    candidate = normalized(key, text) if text else None
    confidences = [token.confidence for token in values]
    return {
        "raw_value": text, "normalized_value": candidate,
        "status": ("READ" if candidate is not None else "AMBIGUOUS") if text else missing,
        "source": "PADDLE_OCR", "unit": "kg" if key in WEIGHTS else "CUSTOM_MEASURE" if key == "gamping" else None,
        "confidence": confidences[0] if len(confidences) == 1 else None,
        "evidence": [token.evidence(asset_id) for token in values],
    }


def rows(tokens):
    if not tokens:
        return []
    tolerance = median(token.bbox[3] for token in tokens) / 2
    grouped = []
    baseline = 0
    for token in sorted(tokens, key=lambda item: item.center[1]):
        if not grouped or token.center[1] - baseline > tolerance:
            grouped.append([])
            baseline = token.center[1]
        grouped[-1].append(token)
    return [sorted(row, key=lambda item: item.center[0]) for row in grouped]


def key_values(lines, mapping, asset):
    found = {}
    for row in lines:
        for index, token in enumerate(row):
            name, delimiter, inline = token.text.partition(":")
            key = mapping.get(label(name))
            if not key:
                continue
            if delimiter and inline.strip():
                values = [Token(inline.strip(), token.confidence, token.bbox)]
            elif index + 1 < len(row) and not mapping.get(label(row[index + 1].text.split(":", 1)[0])):
                values = [row[index + 1]]
            else:
                values = []
            if key in found:
                prior = found[key]
                if field(key, values, asset)["raw_value"] != prior["raw_value"]:
                    prior.update(status="AMBIGUOUS", normalized_value=None)
                    prior["evidence"].extend(item.evidence(asset) for item in values)
                continue
            found[key] = field(key, values, asset, missing="ILLEGIBLE")
    return {key: found.get(key) or field(key, [], asset) for key in mapping.values()}


def table(lines, headings, asset):
    columns = [(COLUMNS.get(label(token.text)), token) for token in headings]
    known = {key for key, _ in columns}
    borders = [(left.center[0] + right.center[0]) / 2 for (_, left), (_, right) in zip(columns, columns[1:])]
    unknown = [{"header_raw": token.text, "column_reference": f"COLUMN-{index+1}", "status": "UNMAPPED",
                "evidence": [token.evidence(asset)]} for index, (key, token) in enumerate(columns) if key is None]
    blocks = []
    active = None
    for line in lines:
        cells = [[] for _ in columns]
        for token in line:
            cells[sum(token.center[0] >= border for border in borders)].append(token)
        named = {key: values for (key, _), values in zip(columns, cells) if key}
        cane = named.get("cane_label", [])
        # A repeated explicit label starts a new block only when the label changes.
        if active is None or (cane and " ".join(token.text for token in cane) != active["cane_label"]["raw_value"]):
            active = {"block_reference": f"BLOCK-{len(blocks)+1}", "cane_label": field("cane_label", cane, asset),
                      "kloter_match": {"status": "NOT_ATTEMPTED", "candidate_kloter_id": None, "match_method": "NONE"},
                      "batches": []}
            blocks.append(active)
        if not any(named.get(key) for key in COLUMNS.values() if key != "cane_label"):
            continue
        values = {key: field(key, named.get(key, []), asset, "ILLEGIBLE" if key in known else "NOT_PRESENT")
                  for key in COLUMNS.values() if key != "cane_label"}
        unmapped = [{"header_raw": token.text, "cell_raw": " ".join(t.text for t in cell), "status": "UNMAPPED",
                     "evidence": [t.evidence(asset) for t in cell]}
                    for (key, token), cell in zip(columns, cells) if key is None and cell]
        active["batches"].append({
            "row_reference": f"ROW-{len(active['batches'])+1}", "pan_number": values["pan_number"],
            "brix": values["brix"], "brix_measurement_stage": "UNKNOWN",
            "cooking": {key: values[key] for key in ("isi_kg", "gamping", "jam_turun")},
            "output": {key: values[key] for key in ("grade", "hasil_kg")}, "unmapped_cells": unmapped,
        })
    return blocks, unknown


def extract(tokens, asset, schema_version, template_version):
    lines = rows(tokens)
    headings = next((index for index, row in enumerate(lines) if {
        "TEBU", "WAJAN", "ISI", "GAMPING", "HASIL",
    } <= {label(token.text) for token in row}), None)
    shared = {"schema_version": schema_version, "template_version": template_version, "issues": []}
    if headings is not None:
        blocks, unknown = table(lines[headings + 1:], lines[headings], asset)
        return {**shared, "document_type": "PRODUCTION_NOTE", "header": key_values(lines[:headings], PRODUCTION, asset),
                "cane_blocks": blocks, "unmapped_columns": unknown}
    header = key_values(lines, TRUCK, asset)
    if sum(value["status"] != "NOT_PRESENT" for value in header.values()) >= 4 and all(
        header[key]["status"] != "NOT_PRESENT" for key in ("vehicle_number", "net_weight_kg")
    ):
        return {**shared, "document_type": "TRUCK_ARRIVAL_NOTE", "header": header, "cane_tag_reference": {
            "raw_value": None, "normalized_code": None, "status": "NOT_CAPTURED",
            "source_note": "Sumber label tebu memerlukan konfirmasi.",
        }}
    return None


def extracted_fields(value, path=""):
    if isinstance(value, dict):
        if "evidence" in value and "normalized_value" in value:
            yield path, value
            return
        items = value.items()
    elif isinstance(value, list):
        items = enumerate(value)
    else:
        return
    for key, child in items:
        yield from extracted_fields(child, f"{path}.{key}" if path else str(key))
