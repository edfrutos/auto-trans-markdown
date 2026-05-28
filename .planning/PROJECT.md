# MarkDown Auto Translator

## What This Is

Traductor de archivos Markdown que preserva formato y bloques de código, orientado a documentación técnica y equipos que localizan docs sin romper sintaxis. Incluye interfaz web (editor, archivo, lote), API FastAPI y proveedores OpenAI o DeepL. Este milestone evoluciona el MVP hacia la hoja de ruta completa del `NOTEBOOK.md` (fases A→E).

## Core Value

Traducir **solo el texto dirigido al usuario** al idioma destino **sin alterar Markdown ni código**, con coherencia terminológica y coste predecible en lotes grandes.

## Requirements

### Validated

- ✓ Segmentación Markdown protegido vs traducible — `src/parser.py`
- ✓ Preservación de bloques ```, inline `code`, frontmatter, indentados — `src/parser.py`
- ✓ Comentarios `#` traducibles en fences shell (bash/sh/zsh/fish) — `src/parser.py`
- ✓ Traducción por lotes vía OpenAI (JSON) o DeepL — `src/translator.py`
- ✓ API REST: texto, archivo único, lote ZIP — `src/main.py`
- ✓ UI web: editor, archivo, lote, modo oscuro, favicon — `static/`
- ✓ Reintentos y chunking en traducción; executor async — `src/translator.py`, `src/main.py`
- ✓ `.env` y secretos fuera de git — `.gitignore`

### Active

- [ ] Glosario / términos fijos (archivo + UI)
- [ ] Memoria de traducción persistente (cache por segmento e idioma)
- [ ] CLI `md-translate` para archivos y directorios (CI/automatización)
- [ ] Validación post-traducción (fences, enlaces, alertas)
- [ ] Vista previa Markdown renderizada en UI
- [ ] Progreso en tiempo real en traducción por lote (SSE/WebSocket)
- [ ] Comentarios traducibles en más lenguajes de código (Python, JS, HTML…)
- [ ] Frontmatter YAML selectivo (title, description…)
- [ ] Multi-destino en una pasada (varios idiomas → ZIP)
- [ ] Estimación de coste/tokens antes de traducir
- [ ] Empaquetado Docker / docker-compose
- [ ] Modo revisión (editar segmentos antes de exportar)
- [ ] Fallback de proveedor (DeepL → OpenAI)
- [ ] Diff visual original vs traducción
- [ ] Carpeta vigilada (watch)
- [ ] Traducción de árbol de directorios / docs site
- [ ] Selector formal/informal (DeepL / LLM)
- [ ] Historial de sesiones (opt-in, sin secretos)
- [ ] Export HTML/PDF opcional

### Out of Scope

- Traducción directa de PDF/DOCX — alcance distinto; pipeline vía MD intermedio
- MT offline sin LLM como calidad principal — inferior en modismos vs OpenAI/DeepL
- Plugin Obsidian/VS Code — repositorio o fase futura separada
- Multi-tenant con API keys por usuario — solo si hay despliegue público; no en este milestone inicial
- Reescritura libre del documento (no traducción) — fuera del propósito del producto

## Context

**Estado actual (brownfield):** Pipeline monolith segment → translate → reassemble. FastAPI + static UI. Sin base de datos. Secretos en `.env`. Roadmap de producto detallado en `NOTEBOOK.md`. Mapa técnico en `.planning/codebase/`.

**Usuarios objetivo:** Desarrolladores, redactores técnicos y equipos que traducen README, docs y artículos Markdown manteniendo código y estructura.

**Deuda conocida:** Sin auth en API, CORS `*`, progreso UI simulado, `output/` sin TTL, `md-translate` script arranca servidor no CLI, frontmatter no traducible selectivamente.

**Decisión de milestone:** Implementar **todo el NOTEBOOK** (fases A→E) como evolución del producto, priorizando orden A→B→C→D→E del notebook.

## Constraints

- **Tech stack**: Mantener Python 3.11+, FastAPI, parser actual; extender sin reescritura total
- **Seguridad**: Nunca commitear `.env`; documentación de planificación sin claves reales
- **Compatibilidad**: OpenAI y DeepL como proveedores; variables de entorno existentes
- **Formato**: Salida siempre Markdown válido; código y URLs intactos
- **Privacidad**: Traducciones y `output/` pueden contener docs privados — gitignore y avisos en UI

## Key Decisions

| Decision | Rationale | Outcome |
| -------- | --------- | ------- |
| Alcance milestone = NOTEBOOK completo (A→E) | Elección explícita del usuario en GSD init | — Pending |
| Mapear codebase antes de planificar | Brownfield con código existente | ✓ Good — `.planning/codebase/` |
| GSD config recomendada (YOLO, Standard, Parallel) | Velocidad con research + verify | — Pending |
| OpenAI por defecto, DeepL alternativo | Ya implementado; glosario favorece LLM | ✓ Good |
| Sin base de datos en MVP; memoria vía SQLite propuesto | NOTEBOOK §2; mínimo acoplamiento | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-28 after GSD initialization (brownfield + NOTEBOOK full scope)*
