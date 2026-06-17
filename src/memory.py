"""Memoria de traducción SQLite (stdlib)."""

from __future__ import annotations

import hashlib
import os
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def default_memory_path() -> Path:
    """Devuelve la ruta de la base de datos de traducción.

    Si la variable de entorno TM_DB_PATH está definida (inyectada por
    ServerManager cuando el usuario activa la sincronización con iCloud Drive),
    se usa esa ruta. En caso contrario se usa el directorio local data/.
    """
    env_path = os.environ.get("TM_DB_PATH", "").strip()
    if env_path:
        p = Path(env_path)
        p.parent.mkdir(parents=True, exist_ok=True)
        return p
    return ROOT / "data" / "translation_memory.db"


def make_key(text: str, source_lang: str | None, target_lang: str) -> str:
    normalized = " ".join(text.split())
    src = source_lang or "auto"
    payload = f"{normalized}|{src}|{target_lang}"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


class TranslationMemory:
    """Cache persistente de segmentos traducidos."""

    def __init__(self, db_path: Path) -> None:
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(self.db_path)
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA synchronous=NORMAL")
        self._conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS translation_memory (
                hash TEXT PRIMARY KEY,
                source_text TEXT NOT NULL,
                source_lang TEXT NOT NULL,
                target_lang TEXT NOT NULL,
                translated_text TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            CREATE INDEX IF NOT EXISTS idx_tm_langs
                ON translation_memory(source_lang, target_lang);
            """
        )
        self._conn.commit()

    def lookup(
        self,
        items: list[tuple[int, str]],
        source_lang: str | None,
        target_lang: str,
    ) -> tuple[dict[int, str], list[tuple[int, str]]]:
        hits: dict[int, str] = {}
        misses: list[tuple[int, str]] = []
        src = source_lang or "auto"
        for idx, text in items:
            key = make_key(text, source_lang, target_lang)
            row = self._conn.execute(
                "SELECT translated_text FROM translation_memory WHERE hash = ?",
                (key,),
            ).fetchone()
            if row:
                hits[idx] = row[0]
            else:
                misses.append((idx, text))
        return hits, misses

    def store_batch(
        self,
        entries: list[tuple[int, str, str]],
        source_lang: str | None,
        target_lang: str,
    ) -> None:
        """Persiste traducciones post-glosario: (idx, source_text, translated_text)."""
        src = source_lang or "auto"
        for _idx, source_text, translated_text in entries:
            key = make_key(source_text, source_lang, target_lang)
            self._conn.execute(
                """
                INSERT INTO translation_memory
                    (hash, source_text, source_lang, target_lang, translated_text, updated_at)
                VALUES (?, ?, ?, ?, ?, datetime('now'))
                ON CONFLICT(hash) DO UPDATE SET
                    translated_text = excluded.translated_text,
                    updated_at = datetime('now')
                """,
                (key, source_text, src, target_lang, translated_text),
            )
        self._conn.commit()

    def clear(self) -> int:
        cur = self._conn.execute("DELETE FROM translation_memory")
        self._conn.commit()
        return cur.rowcount

    def count(self) -> int:
        row = self._conn.execute(
            "SELECT COUNT(*) FROM translation_memory"
        ).fetchone()
        return int(row[0]) if row else 0

    def close(self) -> None:
        self._conn.close()
