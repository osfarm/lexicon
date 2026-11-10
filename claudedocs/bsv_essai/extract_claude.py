"""Trial: extract BSV risks with the Claude API, through the Message Batches API (half price).

Usage:
  python3 -I extract_claude.py submit <bsv_dir> <out_dir> <model> [<model>...]  # one batch, writes <out_dir>/batch.json
  python3 -I extract_claude.py collect <bsv_dir> <out_dir>                      # waits, writes <out_dir>/<model>/<stem>.json

<bsv_dir> holds consigne_extraction.md (system prompt, cached), sample/*.pdf (sent as documents: Claude sees the pages, gauges
and colour tables included) and txt/*.txt (pdftotext output, used only to check the quotes).
Credentials: ANTHROPIC_API_KEY, or an `ant auth login` profile.
"""
import base64
import json
import re
import sys
import time
import unicodedata
from pathlib import Path

import anthropic
from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
from anthropic.types.messages.batch_create_params import Request

LEVELS = ["nul", "faible", "moyen", "fort", "tres_fort", "non_precise"]
TYPES = ["maladie", "ravageur", "adventice", "auxiliaire", "physiologique"]


def nullable(schema):
    return {"anyOf": [schema, {"type": "null"}]}


STRING, INTEGER = {"type": "string"}, {"type": "integer"}

LINE = {
    "type": "object",
    "properties": {
        "culture": STRING,
        "bioagresseur": nullable(STRING),
        "type": nullable({"type": "string", "enum": TYPES}),
        "stade": nullable(STRING),
        "bbch_min": nullable(INTEGER),
        "bbch_max": nullable(INTEGER),
        "niveau": {"type": "string", "enum": LEVELS},
        "niveau_texte": nullable(STRING),
        "periode_risque": nullable(STRING),
        "seuil": nullable(STRING),
        "observations": nullable(STRING),
        "lieux": {"type": "array", "items": STRING},
        "page": nullable(INTEGER),
        "extrait": STRING,
    },
    "additionalProperties": False,
}
LINE["required"] = list(LINE["properties"])

SCHEMA = {
    "type": "object",
    "properties": {
        "region": STRING,
        "zone": nullable(STRING),
        "filiere": STRING,
        "sous_filiere": nullable(STRING),
        "numero": nullable(STRING),
        "date": {"type": "string", "format": "date"},
        "nature": {"type": "string", "enum": ["bulletin", "bilan", "note"]},
        "lignes": {"type": "array", "items": LINE},
        "remarques": nullable(STRING),
    },
    "additionalProperties": False,
}
SCHEMA["required"] = list(SCHEMA["properties"])


def custom_id(index, model):
    """Batch ids allow [a-zA-Z0-9_-]{1,64}."""
    return f"{re.sub(r'[^A-Za-z0-9_-]', '_', model)}-{index:03d}"


def norm(s):
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c)).lower()
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def submit(bsv_dir, out_dir, models):
    system = [{"type": "text", "text": (bsv_dir / "consigne_extraction.md").read_text(), "cache_control": {"type": "ephemeral"}}]
    requests, ids = [], {}
    pdfs = sorted((bsv_dir / "sample").glob("*.pdf"))
    for model in models:
        for i, pdf in enumerate(pdfs):
            cid = custom_id(i, model)
            ids[cid] = [model, pdf.stem]
            data = base64.standard_b64encode(pdf.read_bytes()).decode()
            requests.append(Request(custom_id=cid, params=MessageCreateParamsNonStreaming(
                model=model,
                max_tokens=32000,
                system=system,
                output_config={"effort": "medium", "format": {"type": "json_schema", "schema": SCHEMA}},
                messages=[{"role": "user", "content": [
                    {"type": "document", "source": {"type": "base64", "media_type": "application/pdf", "data": data}},
                    {"type": "text", "text": f"Fichier : {pdf.name}. Extrais ce bulletin selon la consigne."},
                ]}],
            )))
    batch = anthropic.Anthropic().messages.batches.create(requests=requests)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "batch.json").write_text(json.dumps({"id": batch.id, "ids": ids}, indent=1))
    print(f"batch {batch.id}: {len(requests)} requêtes ({len(pdfs)} bulletins x {len(models)} modèles)")


def collect(bsv_dir, out_dir):
    meta = json.loads((out_dir / "batch.json").read_text())
    client = anthropic.Anthropic()
    while (batch := client.messages.batches.retrieve(meta["id"])).processing_status != "ended":
        print(f"{batch.processing_status}: {batch.request_counts.processing} en cours", flush=True)
        time.sleep(60)
    usage = {}
    for result in client.messages.batches.results(meta["id"]):
        model, stem = meta["ids"][result.custom_id]
        if result.result.type != "succeeded":
            print(f"{model} {stem}: {result.result.type}")
            continue
        msg = result.result.message
        if msg.stop_reason != "end_turn":
            print(f"{model} {stem}: stop_reason {msg.stop_reason}")
            continue
        data = json.loads(next(b.text for b in msg.content if b.type == "text"))
        text = norm((bsv_dir / "txt" / f"{stem}.txt").read_text())
        missing = [i for i, line in enumerate(data["lignes"]) if norm(line["extrait"]) not in text]
        data["_controle"] = {"extraits_absents": missing}
        (out_dir / model).mkdir(exist_ok=True)
        (out_dir / model / f"{stem}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1))
        u = msg.usage
        usage.setdefault(model, {"input": 0, "cache_read": 0, "cache_write": 0, "output": 0})
        m = usage[model]
        m["input"] += u.input_tokens
        m["cache_read"] += u.cache_read_input_tokens or 0
        m["cache_write"] += u.cache_creation_input_tokens or 0
        m["output"] += u.output_tokens
        print(f"{model} {stem}: {len(data['lignes'])} lignes, {len(missing)} extraits absents")
    print("tokens", usage)


if __name__ == "__main__":
    action, bsv_dir, out_dir = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    if action == "submit":
        submit(bsv_dir, out_dir, sys.argv[4:] or ["claude-opus-5-5"])
    else:
        collect(bsv_dir, out_dir)
