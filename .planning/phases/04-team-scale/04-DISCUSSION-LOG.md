# Phase 4: Team Scale - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-29
**Phase:** 4-team-scale
**Areas discussed:** Multi-destino UI, Multi-destino backend, Docker, Hardening SEC, CLI multi-idioma

---

## Multi-destino en UI

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-select nativo | select multiple / checkboxes | |
| Chips/tags | etiquetas removibles | ✓ (Claude) |
| Principal + añadir idioma | un idioma + botón | |
| Tú decides | | ✓ (selector) |

**User's choice:** Modos = **todos** (editor, archivo, lote). Selector, estimate y progreso = **Claude decide** → chips; estimate agregado; progreso anidado archivo×idioma.

---

## Multi-destino en backend

| Option | Description | Selected |
|--------|-------------|----------|
| Por archivo luego idiomas | file_then_lang | ✓ |
| Por idioma luego archivos | lang_then_file | |
| Serial | concurrencia 1 | |
| Env MULTI_LANG_CONCURRENCY | configurable | ✓ (Claude, default 1) |
| ZIP plano stem.{lang}.md | MULTI-02 | ✓ (Claude) |
| target_lang + target_langs[] | compatibilidad | ✓ |

---

## Docker y despliegue

| Option | Description | Selected |
|--------|-------------|----------|
| LAN + VPS documentados | both | ✓ |
| requirements.txt vs uv.lock | brownfield | ✓ (Claude → requirements.txt) |
| Compose minimal + healthcheck | | ✓ (Claude) |
| Puerto 5400 default | usuario free-text | ✓ |

---

## Hardening SEC

| Option | Description | Selected |
|--------|-------------|----------|
| CORS_ORIGINS comma-separated | | ✓ |
| Límite por archivo Y total batch | | ✓ |
| TTL arranque + periódico | | ✓ |
| Sin auth obligatorio | | ✓ (Claude; API_TOKEN opcional) |

---

## CLI multi-idioma

| Option | Description | Selected |
|--------|-------------|----------|
| Paridad web file/dir/batch | | ✓ |
| `-t es,en,fr` | coma separada | ✓ |
| Salida stem.{lang}.md | | ✓ |

---

## Claude's Discretion

- Chips UI implementation details
- validation.json naming multi-idioma
- API_TOKEN optional gate vs docs-only
- Default TTL and MB limits
- Compose dev/prod profile naming

## Deferred Ideas

- uv.lock introduction
- ZIP folders by language
- Mandatory auth (V2-03)
