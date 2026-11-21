"""Text of the pages of a decision of derogation, for `Derogations::Reader`.

The text layer is read with PyMuPDF (pymupdf4llm writes the tables as markdown tables, which keeps the lines of
usages apart). A page with no text layer, a scan, is read by Tesseract, which pymupdf4llm calls itself. Prints JSON
on stdout:

    {"engine": "pymupdf4llm 2.1", "pages": [{"index": 0, "markdown": "...", "ocr": false}, ...]}

Usage: python3 ocr.py <file.pdf>
"""
import contextlib
import json
import sys
from importlib.metadata import version


def pages(path):
    import pymupdf
    import pymupdf4llm

    document = pymupdf.open(path)
    chunks = pymupdf4llm.to_markdown(document, page_chunks=True, show_progress=False)
    return [
        # `ocr`: the page has no text layer, pymupdf4llm had Tesseract read it
        {"index": index, "markdown": chunk.get("text") or "", "ocr": not document[index].get_text().strip()}
        for index, chunk in enumerate(chunks)
    ]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: ocr.py <file.pdf>")
    # pymupdf4llm prints its messages on stdout, from its import on: they go to stderr, stdout is for the JSON only
    with contextlib.redirect_stdout(sys.stderr):
        read = pages(sys.argv[1])
    json.dump({"engine": f"pymupdf4llm {version('pymupdf4llm')}", "pages": read}, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
