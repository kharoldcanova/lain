"""Utilidades compartidas por los scripts de inferencia."""

from pathlib import Path


def newest_gguf(directory: Path) -> Path | None:
    """Devuelve el .gguf más reciente: outputs/ puede tener varios modelos base."""
    candidates = list(Path(directory).glob("*.gguf"))
    return max(candidates, key=lambda path: path.stat().st_mtime) if candidates else None
