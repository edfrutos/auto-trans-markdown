"""Glosario YAML: términos DNT y traducciones fijas por par de idiomas."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

import yaml

MAX_GLOSSARY_BYTES = 256 * 1024
GLO_PLACEHOLDER = "⟦GLO{n}⟧"


@dataclass
class GlossaryRules:
    do_not_translate: list[str] = field(default_factory=list)
    pairs: dict[str, str] = field(default_factory=dict)

    @property
    def has_rules(self) -> bool:
        return bool(self.do_not_translate or self.pairs)


@dataclass
class Glossary:
    version: int = 1
    do_not_translate: list[str] = field(default_factory=list)
    pairs: dict[str, dict[str, str]] = field(default_factory=dict)

    def get_rules(self, source_lang: str | None, target_lang: str) -> GlossaryRules:
        src = source_lang or "auto"
        pair_keys = [f"{src}-{target_lang}", f"auto-{target_lang}"]
        merged: dict[str, str] = {}
        for key in pair_keys:
            for term, translation in self.pairs.get(key, {}).items():
                merged[term] = translation
        return GlossaryRules(
            do_not_translate=list(self.do_not_translate),
            pairs=merged,
        )


@dataclass
class GlossaryPreState:
    placeholders: dict[str, str]


def load_glossary(path: Path) -> Glossary:
    if not path.exists():
        return Glossary()
    raw = path.read_bytes()
    if len(raw) > MAX_GLOSSARY_BYTES:
        raise ValueError("El glosario supera el tamaño máximo permitido (256 KB)")
    data = yaml.safe_load(raw.decode("utf-8"))
    if not data:
        return Glossary()
    if not isinstance(data, dict):
        raise ValueError("Formato de glosario inválido")
    version = data.get("version", 1)
    if version != 1:
        raise ValueError("Solo se admite version: 1")
    dnt = data.get("do_not_translate") or []
    pairs = data.get("pairs") or {}
    if not isinstance(dnt, list) or not isinstance(pairs, dict):
        raise ValueError("Esquema de glosario inválido")
    return Glossary(version=1, do_not_translate=[str(x) for x in dnt], pairs=pairs)


def save_glossary(path: Path, glossary: Glossary) -> None:
    payload = {
        "version": glossary.version,
        "do_not_translate": glossary.do_not_translate,
        "pairs": glossary.pairs,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        yaml.safe_dump(payload, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def glossary_to_dict(glossary: Glossary) -> dict:
    return {
        "version": glossary.version,
        "do_not_translate": glossary.do_not_translate,
        "pairs": glossary.pairs,
    }


def glossary_from_dict(data: dict) -> Glossary:
    g = Glossary(
        version=int(data.get("version", 1)),
        do_not_translate=list(data.get("do_not_translate") or []),
        pairs=dict(data.get("pairs") or {}),
    )
    if g.version != 1:
        raise ValueError("Solo se admite version: 1")
    _validate_pairs(g.pairs)
    return g


def _validate_pairs(pairs: dict) -> None:
    pair_key_re = re.compile(
        r"^[a-z]{2}(-[A-Z]{2})?-(auto|[a-z]{2}(-[A-Z]{2})?)$"
    )
    for key, mapping in pairs.items():
        if not pair_key_re.match(key):
            raise ValueError(f"Clave de par inválida: {key}")
        if not isinstance(mapping, dict):
            raise ValueError(f"Par {key} debe ser un objeto de términos")
        for term, val in mapping.items():
            if not isinstance(term, str) or not isinstance(val, str):
                raise ValueError(f"Entrada inválida en par {key}")


def _sorted_terms(rules: GlossaryRules) -> list[tuple[str, str | None]]:
    """Longest-match-first: (term, fixed_translation or None for DNT)."""
    entries: list[tuple[str, str | None]] = []
    for term in rules.do_not_translate:
        entries.append((term, None))
    for term, translation in rules.pairs.items():
        entries.append((term, translation))
    entries.sort(key=lambda x: len(x[0]), reverse=True)
    return entries


def apply_pre(
    text: str,
    rules: GlossaryRules,
    provider: str,
) -> tuple[str, GlossaryPreState | None]:
    if not rules.has_rules:
        return text, None
    entries = _sorted_terms(rules)
    if provider == "deepl":
        return _apply_pre_deepl(text, entries)
    return text, GlossaryPreState(placeholders={})


def _apply_pre_deepl(
    text: str,
    entries: list[tuple[str, str | None]],
) -> tuple[str, GlossaryPreState]:
    result = text
    placeholders: dict[str, str] = {}
    counter = 0
    for term, fixed in entries:
        if term not in result:
            continue
        token = GLO_PLACEHOLDER.format(n=counter)
        counter += 1
        replacement = token
        placeholders[token] = fixed if fixed is not None else term
        result = result.replace(term, replacement)
    return result, GlossaryPreState(placeholders=placeholders)


def apply_post(
    text: str,
    state: GlossaryPreState | None,
    rules: GlossaryRules,
) -> str:
    if state and state.placeholders:
        result = text
        for token, replacement in state.placeholders.items():
            result = result.replace(token, replacement)
        return result
    if not rules.has_rules:
        return text
    result = text
    for term, fixed in _sorted_terms(rules):
        if fixed is not None and term in result:
            result = result.replace(term, fixed)
    return result


def build_prompt_appendix(rules: GlossaryRules) -> str:
    if not rules.has_rules:
        return ""
    lines = ["GLOSSARY RULES (mandatory):"]
    if rules.do_not_translate:
        lines.append(
            "- Do NOT translate: " + ", ".join(rules.do_not_translate)
        )
    if rules.pairs:
        pair_lines = [
            f'"{src}" → "{dst}"' for src, dst in rules.pairs.items()
        ]
        lines.append("- Fixed translations: " + "; ".join(pair_lines))
    return "\n".join(lines)
