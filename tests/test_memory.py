"""Tests de memoria de traducción SQLite."""

from __future__ import annotations

from src.memory import TranslationMemory, make_key


def test_store_and_lookup_hit(tmp_path):
    db = tmp_path / "tm.db"
    tm = TranslationMemory(db)
    items = [(0, "Hello  world")]
    hits, misses = tm.lookup(items, None, "es")
    assert misses == items
    tm.store_batch([(0, "Hello  world", "Hola mundo")], None, "es")
    hits2, misses2 = tm.lookup(items, None, "es")
    assert misses2 == []
    assert hits2[0] == "Hola mundo"


def test_normalize_whitespace_in_key():
    k1 = make_key("Hello   world", None, "es")
    k2 = make_key("Hello world", None, "es")
    assert k1 == k2


def test_clear_and_count(tmp_path):
    db = tmp_path / "tm.db"
    tm = TranslationMemory(db)
    tm.store_batch([(0, "a", "b")], "en", "es")
    assert tm.count() == 1
    deleted = tm.clear()
    assert deleted == 1
    assert tm.count() == 0


def test_different_target_lang_miss(tmp_path):
    db = tmp_path / "tm.db"
    tm = TranslationMemory(db)
    tm.store_batch([(0, "Hi", "Hola")], None, "es")
    hits, misses = tm.lookup([(0, "Hi")], None, "fr")
    assert misses == [(0, "Hi")]
    assert hits == {}
