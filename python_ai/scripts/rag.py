"""RAG local para LAIN: descarga, indexa y recupera conocimiento en SQLite.

Uso:
    python scripts/rag.py ingest https://ejemplo.com/nota
    python scripts/rag.py ingest --file datos/nota.md
    python scripts/rag.py query "¿qué es la teoría X?" --top-k 4
    python scripts/rag.py stats
    python scripts/rag.py clear

Los embeddings se calculan on-device con multilingual-e5-small y se guardan
en rag/lain_rag.db. Sin red, las consultas siguen funcionando con lo indexado.
"""

import argparse
import hashlib
import sqlite3
import urllib.request
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path

import numpy as np
from sentence_transformers import SentenceTransformer

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "rag" / "lain_rag.db"
MODEL_NAME = "intfloat/multilingual-e5-small"
CHUNK_CHARS = 1000
CHUNK_OVERLAP = 150
MAX_BYTES = 5 * 1024 * 1024
BLOCK_TAGS = {
    "p", "div", "section", "article", "br", "li", "tr",
    "h1", "h2", "h3", "h4", "h5", "h6", "pre", "blockquote",
}

_model = None


def get_model():
    global _model
    if _model is None:
        _model = SentenceTransformer(MODEL_NAME)
    return _model


class TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "noscript"):
            self.skip += 1
        elif tag in BLOCK_TAGS:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in ("script", "style", "noscript") and self.skip:
            self.skip -= 1
        elif tag in BLOCK_TAGS:
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)

    def text(self):
        return "".join(self.parts)


def html_to_text(raw):
    parser = TextExtractor()
    parser.feed(raw)
    lines = [" ".join(line.split()) for line in parser.text().splitlines()]
    return "\n".join(line for line in lines if line)


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "LAIN-local-rag/1.0"})
    with urllib.request.urlopen(request, timeout=20) as response:
        data = response.read(MAX_BYTES)
        charset = response.headers.get_content_charset() or "utf-8"
    return data.decode(charset, errors="replace")


def read_source(source, is_file):
    if is_file:
        return Path(source).expanduser().read_text(encoding="utf-8")
    if not source.startswith(("http://", "https://")):
        raise SystemExit("Solo se admiten URLs http(s) o --file para archivos locales.")
    raw = fetch(source)
    return html_to_text(raw) if "<html" in raw[:2000].lower() else raw


def chunk_text(text, size=CHUNK_CHARS, overlap=CHUNK_OVERLAP):
    paragraphs = [p.strip() for p in text.split("\n") if p.strip()]
    chunks, current = [], ""
    for paragraph in paragraphs:
        if len(current) + len(paragraph) + 1 <= size:
            current = f"{current}\n{paragraph}".strip()
            continue
        if current:
            chunks.append(current)
        current = (current[-overlap:] + "\n" + paragraph).strip() if current else paragraph
        while len(current) > size:
            chunks.append(current[:size])
            current = current[size - overlap:]
    if current:
        chunks.append(current)
    return [c for c in chunks if len(c) >= 50]


def connect():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS documents (
            id INTEGER PRIMARY KEY,
            source TEXT UNIQUE NOT NULL,
            title TEXT,
            fetched_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS chunks (
            id INTEGER PRIMARY KEY,
            document_id INTEGER NOT NULL,
            position INTEGER NOT NULL,
            text TEXT NOT NULL,
            embedding BLOB NOT NULL,
            FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
        );
        """
    )
    return conn


def embed(texts, prefix):
    model = get_model()
    vectors = model.encode(
        [f"{prefix}{text}" for text in texts],
        normalize_embeddings=True,
        show_progress_bar=False,
    )
    return vectors.astype("float32")


def ingest(source, is_file=False):
    text = read_source(source, is_file)
    chunks = chunk_text(text)
    if not chunks:
        raise SystemExit("No se extrajo texto útil de la fuente.")

    vectors = embed(chunks, "passage: ")
    title = Path(source).stem if is_file else source
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    conn = connect()
    with conn:
        conn.execute("DELETE FROM documents WHERE source = ?", (source,))
        cursor = conn.execute(
            "INSERT INTO documents (source, title, fetched_at) VALUES (?, ?, ?)",
            (source, title, now),
        )
        doc_id = cursor.lastrowid
        conn.executemany(
            "INSERT INTO chunks (document_id, position, text, embedding) VALUES (?, ?, ?, ?)",
            [
                (doc_id, i, chunk, vector.tobytes())
                for i, (chunk, vector) in enumerate(zip(chunks, vectors))
            ],
        )
    conn.close()
    print(f"Indexados {len(chunks)} fragmentos de {source}")


def search(query, top_k=4):
    if not DB_PATH.exists():
        return []
    conn = connect()
    rows = conn.execute(
        "SELECT c.text, c.embedding, d.source FROM chunks c JOIN documents d ON d.id = c.document_id"
    ).fetchall()
    conn.close()
    if not rows:
        return []

    matrix = np.vstack([np.frombuffer(row[1], dtype="float32") for row in rows])
    scores = matrix @ embed([query], "query: ")[0]
    order = np.argsort(scores)[::-1][:top_k]
    return [
        {"score": float(scores[i]), "text": rows[i][0], "source": rows[i][2]}
        for i in order
    ]


def stats():
    if not DB_PATH.exists():
        print("Base vacía. Usa: python scripts/rag.py ingest <url|--file ruta>")
        return
    conn = connect()
    documents = conn.execute("SELECT COUNT(*) FROM documents").fetchone()[0]
    chunks = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
    conn.close()
    print(f"Documentos: {documents} | Fragmentos: {chunks} | DB: {DB_PATH}")


def clear():
    if DB_PATH.exists():
        DB_PATH.unlink()
    print("Base RAG eliminada.")


def main():
    parser = argparse.ArgumentParser(description="RAG local para LAIN.")
    sub = parser.add_subparsers(dest="command", required=True)

    ingest_cmd = sub.add_parser("ingest", help="Indexa una URL o un archivo local.")
    ingest_cmd.add_argument("source")
    ingest_cmd.add_argument("--file", action="store_true", help="Interpretar source como ruta local.")

    query_cmd = sub.add_parser("query", help="Busca fragmentos relevantes.")
    query_cmd.add_argument("query")
    query_cmd.add_argument("--top-k", type=int, default=4)

    sub.add_parser("stats", help="Muestra el estado de la base.")
    sub.add_parser("clear", help="Borra la base RAG.")

    args = parser.parse_args()
    if args.command == "ingest":
        ingest(args.source, is_file=args.file)
    elif args.command == "query":
        results = search(args.query, args.top_k)
        if not results:
            print("Sin resultados. Indexa algo primero.")
            return
        for index, hit in enumerate(results, 1):
            print(f"[{index}] score={hit['score']:.3f} source={hit['source']}")
            print(f"    {hit['text'][:400]}\n")
    elif args.command == "stats":
        stats()
    elif args.command == "clear":
        clear()


if __name__ == "__main__":
    main()
