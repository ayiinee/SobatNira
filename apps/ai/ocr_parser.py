from dataclasses import dataclass
from datetime import date
from itertools import takewhile
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
COOKING_HEADERS = {"pan_number", "isi_kg", "gamping"}
SUPPLIER_MIN_CONFIDENCE = 0.90
SUPPLIER_INLINE = re.compile(r"^PENGIRIM\s+(.+)$", re.I)
HEADER_WORDS = "|".join(re.escape(name) for name in sorted(COLUMNS, key=len, reverse=True))
HEADER_PATTERN = re.compile(HEADER_WORDS, re.I)
MERGED_HEADERS = re.compile(rf"(?:{HEADER_WORDS})(?:[\s|/,:;-]*(?:{HEADER_WORDS}))+", re.I)


@dataclass(frozen=True)
class Column:
    key: str | None
    token: Token
    center_x: float


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
    confidence = values[0].confidence if len(values) == 1 else None
    if key == "supplier_name" and values:
        confidence = min(token.confidence for token in values) if all(token.confidence is not None for token in values) else None
        if confidence is None or confidence < SUPPLIER_MIN_CONFIDENCE or not any(char.isalpha() for char in text):
            candidate = None
    return {
        "raw_value": text, "normalized_value": candidate,
        "status": ("READ" if candidate is not None else "AMBIGUOUS") if text else missing,
        "source": "PADDLE_OCR", "unit": "kg" if key in WEIGHTS else "CUSTOM_MEASURE" if key == "gamping" else None,
        "confidence": confidence,
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
            if not delimiter and key is None and "PENGIRIM" in mapping:
                if match := SUPPLIER_INLINE.fullmatch(token.text.strip()):
                    key, delimiter, inline = "supplier_name", " ", match[1]
            if not key:
                continue
            values = [Token(inline.strip(), token.confidence, token.bbox)] if delimiter and inline.strip() else []
            following = takewhile(lambda item: not mapping.get(label(item.text.split(":", 1)[0])), row[index + 1:])
            if key == "supplier_name":
                values.extend(following)
            elif not values and (value := next(following, None)) is not None:
                values.append(value)
            entry = field(key, values, asset, missing="ILLEGIBLE")
            if key in found:
                prior = found[key]
                if entry["raw_value"] != prior["raw_value"]:
                    prior.update(status="AMBIGUOUS", normalized_value=None)
                    prior["evidence"].extend(item.evidence(asset) for item in values)
                continue
            found[key] = entry
    return {key: found.get(key) or field(key, [], asset) for key in mapping.values()}


def table_columns(row):
    columns = []
    for token in row:
        name = label(token.text)
        text = token.text.strip()
        if name in COLUMNS or not MERGED_HEADERS.fullmatch(text):
            columns.append(Column(COLUMNS.get(name), token, token.center[0]))
            continue
        # Paddle exposes one box for the entire merged header. Character offsets
        # guide column assignment, while evidence always uses the original OCR box.
        x, _, width, _ = token.bbox
        for match in HEADER_PATTERN.finditer(text):
            center = x + width * (match.start() + match.end()) / (2 * len(text))
            columns.append(Column(COLUMNS[label(match[0])], token, center))
    return sorted(columns, key=lambda column: column.center_x)


def table(lines, columns, asset):
    known = {column.key for column in columns}
    borders = [(left.center_x + right.center_x) / 2 for left, right in zip(columns, columns[1:])]
    unknown = [{"header_raw": column.token.text, "column_reference": f"COLUMN-{index+1}", "status": "UNMAPPED",
                "evidence": [column.token.evidence(asset)]} for index, column in enumerate(columns) if column.key is None]
    blocks = []
    active = None
    for line in lines:
        cells = [[] for _ in columns]
        for token in line:
            cells[sum(token.center[0] >= border for border in borders)].append(token)
        named = {column.key: values for column, values in zip(columns, cells) if column.key}
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
        unmapped = [{"header_raw": column.token.text, "cell_raw": " ".join(t.text for t in cell), "status": "UNMAPPED",
                     "evidence": [t.evidence(asset) for t in cell]}
                    for column, cell in zip(columns, cells) if column.key is None and cell]
        active["batches"].append({
            "row_reference": f"ROW-{len(active['batches'])+1}", "pan_number": values["pan_number"],
            "brix": values["brix"], "brix_measurement_stage": "UNKNOWN",
            "cooking": {key: values[key] for key in ("isi_kg", "gamping", "jam_turun")},
            "output": {key: values[key] for key in ("grade", "hasil_kg")}, "unmapped_cells": unmapped,
        })
    return blocks, unknown


def extract(tokens, asset, schema_version, template_version):
    lines = rows(tokens)
    shared = {"schema_version": schema_version, "template_version": template_version, "issues": []}
    for index, row in enumerate(lines):
        columns = table_columns(row)
        keys = [column.key for column in columns if column.key is not None]
        if COOKING_HEADERS <= set(keys) and len(keys) == len(set(keys)):
            blocks, unknown = table(lines[index + 1:], columns, asset)
            if any(batch["pan_number"]["raw_value"] and (
                batch["cooking"]["isi_kg"]["raw_value"] or batch["cooking"]["gamping"]["raw_value"]
            ) for block in blocks for batch in block["batches"]):
                return {**shared, "document_type": "PRODUCTION_NOTE", "header": key_values(lines[:index], PRODUCTION, asset),
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
