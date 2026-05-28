# Feature Landscape

**Domain:** Markdown / technical documentation translation tools  
**Project:** MarkDown Auto Translator (milestone SUBSEQUENT — NOTEBOOK A→E)  
**Researched:** 2026-05-28

## Executive framing

Tools in this space split into **format-safe segment-and-translate pipelines** (md-translator, rosetta-mark, Lara/MetalGlot-style MD processors) and **general CAT/i18n platforms** (Glossboss, PO/JSON workflows). For **developer docs in Markdown**, users judge quality first on **what stayed intact** (code, links, frontmatter keys, fences), then on **terminology consistency** and **operational fit** (batch, CI, cost). This project already covers most **table stakes** in its MVP; the NOTEBOOK backlog moves from **production hygiene** (glossary, TM, CLI, validation) toward **team deployment and editorial workflow** (Docker, multi-target, review, watch).

**Confidence:** Table stakes and anti-features — **HIGH** (validated in codebase + multiple industry sources). Competitive differentiator ranking — **MEDIUM** (WebSearch + GitHub READMEs; not a formal market study).

---

## Table Stakes

Features users expect from any credible Markdown translation tool. Missing these makes the product feel broken or unsafe for technical docs.

| Feature | Why expected | Complexity | Project status |
|---------|--------------|------------|----------------|
| **Segmentación protegido vs traducible** | Industry standard: only prose is translated; code/structure must survive parsers and builds | Med | ✓ Validated — `src/parser.py` |
| **Preservar bloques ` ``` `, inline `` ` ``, indentados** | #1 failure mode in MD localization (broken fences → unreadable docs) | Med | ✓ Validated |
| **Preservar estructura MD** (encabezados, listas, tablas, enlaces, imágenes) | Readers expect same outline and link targets | Med | ✓ Validated (reassemble) |
| **No traducir URLs, rutas, identificadores, claves API** | Broken links and copy-paste failures | Low–Med | ✓ Implicit in protected segments; validation not automated |
| **Frontmatter YAML protegido** (bloque intacto) | SSGs break if keys or types change | Med | ✓ Protected as block; selective field translation = gap |
| **Traducción archivo único + salida `.md`** | README/docs workflow | Low | ✓ API + UI |
| **Traducción por lote** (múltiples archivos) | Real doc sets are folders, not one file | Med | ✓ ZIP batch (max 20 files) |
| **Múltiples idiomas origen/destino** | Any serious localization tool | Low | ✓ 30+ codes; DeepL subset documented |
| **Proveedor MT/LLM con API key** (BYOK) | No hosted MT without user credentials for private docs | Low | ✓ OpenAI + DeepL |
| **Interfaz usable sin escribir código** | Tech writers and PMs, not only engineers | Med | ✓ Web UI (editor, archivo, lote) |
| **API programática** (mismo motor que UI) | Automation and integrations | Med | ✓ FastAPI |
| **Reintentos / resiliencia ante rate limits** | Batch jobs always hit 429 | Med | ✓ `src/translator.py` |
| **Modismos / traducción contextual** (LLM path) | Literal MT on colloquial prose reads wrong | Med | ✓ OpenAI default positioning |

### Table stakes — partially met (gaps vs ecosystem)

| Feature | Why expected | Complexity | Project status |
|---------|--------------|------------|----------------|
| **Glosario / lista «no traducir»** | Terminology lock is standard in CAT and MD tools (rosetta-mark, Lara, OpenL) | Med | NOTEBOOK §1 — Active |
| **Coherencia frase repetida en lotes** | Same string → same translation across files | Med | NOTEBOOK §2 (TM) — Active; competitors use TM/SQLite/cache |
| **CLI / CI sin servidor web** | Pipelines and pre-commit are table stakes for dev teams | Med | NOTEBOOK §3 — Active; script name exists but not true CLI |
| **Comprobación post-traducción** (fences, enlaces) | Catches silent structure breaks before merge | Med | NOTEBOOK §6 — Active |
| **Progreso real en lote** | Long jobs without feedback feel broken | Med | NOTEBOOK §5 — Active (UI progress simulated per PROJECT.md) |

---

## Differentiators

Features that set a product apart. Not always expected on day one, but valued for **technical docs at scale**, **cost control**, or **editorial quality**.

| Feature | Value proposition | Complexity | NOTEBOOK | Phase |
|---------|-------------------|------------|----------|-------|
| **Memoria de traducción persistente** | Lower API cost, speed, identical phrasing across repo | Med | §2 | A |
| **Glosario por par de idiomas + UI** | Product names, APIs, agreed renderings | Med | §1 | A |
| **CLI `md-translate` (file, dir, batch, dry-run)** | GitHub Actions, local scripts, no browser | Med | §3 | A |
| **Vista previa MD renderizada + sanitización** | Visual QA for tables/lists before export | Med | §4 | B |
| **Validación estructural + informe JSON en ZIP** | Automated gate before publishing | Med | §6 | B |
| **Comentarios traducibles en más lenguajes** | Docs with explanatory code in py/js/sql/html | Med–High | §7 | B (stretch) |
| **Frontmatter YAML selectivo** | SEO fields translated, `slug`/`layout` preserved | Med | §8 | B |
| **SSE/WebSocket progreso + cancelación job** | Trust on 10–20+ file batches | Med | §5 | C |
| **Estimación coste/tokens pre-traducción** | Budget approval before spend | Low–Med | §10 | C |
| **Multi-destino en una pasada** | One upload → `doc.es.md`, `doc.fr.md`, … | High | §9 | D |
| **Docker / docker-compose** | One-command team deploy | Med | §11 | D |
| **Modo revisión segmento a segmento** | Human-in-the-loop for legal/release notes | High | §12 | E |
| **Fallback proveedor (DeepL → OpenAI)** | Uptime when quota/language unsupported | Low–Med | §13 | E (low effort) |
| **Diff visual original vs traducción** | Reviewer UX without external diff tool | Med | §14 | E |
| **Watch carpeta `input/` → `output/`** | Live authoring (Obsidian/VS Code save) | High | §15 | E |
| **Árbol directorios / docs site + `.gitignore` respect** | Whole site localization | High | §16 | E |
| **Formal / informal (DeepL formality + LLM tone)** | Locale-appropriate register | Low | §17 | E (low effort) |
| **Historial sesiones (opt-in, sin secretos)** | Convenience without TM scope | Med | §18 | E |
| **Export HTML/PDF** | Deliverables beyond MD | High | §19 | E (optional) |

### Differentiators already in MVP (positioning, not backlog)

| Feature | Notes |
|---------|-------|
| **Comentarios `#` en fences shell** | Uncommon depth vs generic MD translators; keep as marketing differentiator |
| **Dual provider OpenAI + DeepL** | Table stake for flexibility; **fallback chain** is the differentiator (§13) |
| **Modo editor en vivo** | Strong for ad-hoc strings; less common in pure CLI tools |

### Weak differentiators for this product (defer or out of scope)

| Feature | Why weak here |
|---------|---------------|
| **Multi-tenant API key per user** | NOTEBOOK §20 — only if public SaaS; PROJECT.md Out of Scope for milestone |
| **Plugin Obsidian/VS Code** | Different distribution model; NOTEBOOK «fase F» |
| **MT offline sin LLM como calidad principal** | Out of Scope — inferior for modismos |
| **PDF/DOCX direct** | Out of Scope — different pipeline |

---

## Anti-Features

Features to explicitly **not** build in this milestone (or ever, per product intent).

| Anti-Feature | Why avoid | What to do instead |
|--------------|-----------|-------------------|
| **Traducir PDF/DOCX in-place** | Different parsers, layout, and QA | MD intermediate pipeline if needed later |
| **MT offline como motor principal** | Poor modismos vs OpenAI/DeepL | Keep cloud providers; optional local via `OPENAI_BASE_URL` only |
| **Plugin IDE (Obsidian/VS Code)** | Separate repo, release cadence, marketplace | Ship CLI + API; users wire editor save → watch (§15) later |
| **Multi-tenant con claves por usuario** | Security/compliance scope explosion | BYOK via `.env` on single host; revisit only for public deploy |
| **Reescritura libre / «mejorar redacción»** | Conflicts with core value (faithful translation) | Stay on segment translate + glossary |
| **Traducir claves YAML, URLs, código, flags CLI** | Breaks builds and copy-paste | Protected segments + validator + glossary DNT list |
| **CORS `*` + sin auth en despliegue público** | Data exfiltration risk | Document «local/trusted network»; auth phase only if SaaS |

---

## NOTEBOOK → Landscape mapping

Complete map of `NOTEBOOK.md` items (§1–§20) to category, phase, and dependency notes.

| ID | NOTEBOOK title | Priority | Effort | Category | Phase | Depends on / notes |
|----|----------------|----------|--------|----------|-------|-------------------|
| 1 | Glosario y términos fijos | 🔴 | ⚙️⚙️ | **Table stake** (docs teams) / **Differentiator** (generic MD tools) | A | Feeds TM consistency; OpenAI prompt injection + DeepL placeholders |
| 2 | Memoria de traducción | 🔴 | ⚙️⚙️ | **Differentiator** | A | SQLite per PROJECT decision; before cost estimate accuracy |
| 3 | CLI automatización | 🔴 | ⚙️⚙️ | **Table stake** (CI) | A | Reuses `parser`, `translator`; exit codes for CI |
| 4 | Vista previa MD renderizada | 🔴 | ⚙️⚙️ | **Differentiator** | B | Sanitize HTML; pairs with §6 validation |
| 5 | Progreso tiempo real (lote) | 🔴 | ⚙️⚙️ | **Table stake gap** | C | SSE/WS + job id; optional Redis only at scale |
| 6 | Validación post-traducción | 🟡 | ⚙️⚙️ | **Table stake gap** | B | `src/validator.py`; blocks download optional |
| 7 | Comentarios más lenguajes | 🟡 | ⚙️⚙️ | **Differentiator** | B | Extends `parser.py`; tests per language |
| 8 | Frontmatter YAML selectivo | 🟡 | ⚙️⚙️ | **Differentiator** | B | PyYAML whitelist; fallback protect whole block |
| 9 | Multi-destino una pasada | 🟢 | ⚙️⚙️⚙️ | **Differentiator** | D | Concurrency limits; shares §2 TM per source segment |
| 10 | Estimación coste/tokens | 🟢 | ⚙️ | **Differentiator** | C | `collect_translatable()` + price table; pairs §5 |
| 11 | Docker y despliegue | 🟢 | ⚙️⚙️ | **Differentiator** (ops) | D | Volumes for `output/` + TM DB |
| 12 | Modo revisión (borrador) | 🟢 | ⚙️⚙️⚙️ | **Differentiator** | E | Segment UI; export gate |
| 13 | Proveedor con fallback | ⚙️ | ⚙️⚙️ | **Differentiator** | E | `TRANSLATION_FALLBACK`; small win early if moved up |
| 14 | Diff visual | ⚙️ | ⚙️⚙️ | **Differentiator** | E | Complements §4 preview |
| 15 | Carpeta vigilada (watch) | ⚙️ | ⚙️⚙️⚙️ | **Differentiator** | E | Dev workflow; not substitute for §3 CLI in CI |
| 16 | Árbol Git / docs site | ⚙️ | ⚙️⚙️⚙️ | **Differentiator** | E | Extends batch + `.gitignore` rules |
| 17 | Formal / informal | ⚙️ | ⚙️ | **Differentiator** | E | DeepL `formality`; LLM prompt variant |
| 18 | Historial sesiones | ⚙️ | ⚙️⚙️ | **Differentiator** (convenience) | E | Opt-in privacy; not TM |
| 19 | Export HTML/PDF | ⚙️ | ⚙️⚙️⚙️ | **Differentiator** (optional) | E | Pandoc/WeasyPrint; out of core MD path |
| 20 | API key por usuario | ⚙️ | ⚙️⚙️⚙️ | **Anti-feature** (this milestone) | — | PROJECT Out of Scope unless public SaaS |

### NOTEBOOK phased delivery vs feature type

| Phase | NOTEBOOK deliverables | Primary feature goal |
|-------|----------------------|----------------------|
| **A** | §1 Glosario, §2 TM, §3 CLI | **Production table stakes** for tech docs + automation |
| **B** | §6 Validación, §4 Preview (+ §7–§8 quality extensions) | **Trust** — catch breaks before ship |
| **C** | §5 Progreso SSE, §10 Estimación | **UX + cost control** on large batches |
| **D** | §9 Multi-destino, §11 Docker | **Team scale** — deploy and multi-locale output |
| **E** | §12 Revisión, §15 Watch, §14 Diff (+ §13–§19 polish) | **Editorial / pro workflow** |

### Ideas descartadas (NOTEBOOK footer) → Anti-features

| NOTEBOOK discarded idea | Mapped to |
|-------------------------|-----------|
| PDF/DOCX directo | Anti-feature |
| MT offline sin LLM | Anti-feature |
| Plugin Obsidian/VS Code | Anti-feature (separate product) |

---

## Feature Dependencies

```
parser (segmentación) ──► translator ──► reassemble
         │                      │
         │                      ├──► glossary (§1) ──► prompt / placeholders
         │                      └──► translation memory (§2) ──► cache before API
         │
         ├──► validator (§6) ──► post reassemble
         ├──► frontmatter selective (§8) ──► parser extension
         └──► code comments i18n (§7) ──► parser extension

CLI (§3) ──► same pipeline as API (no web)

estimate (§10) ──► collect_translatable() only (no provider call)

batch SSE (§5) ──► async jobs + batch translator
multi-target (§9) ──► parallel jobs per lang + TM keyed by target_lang

preview (§4) ──► client render (independent)
diff (§14) ──► needs translated + source text (pairs with preview/review)

review mode (§12) ──► segment list API + UI state before export

watch (§15) / docs tree (§16) ──► CLI or internal batch runner + filesystem

docker (§11) ──► packages API+static; volumes for output + TM

fallback (§13) ──► translator provider chain
```

**Critical path for roadmap:** §1 + §2 + §3 (Phase A) unlock terminology and CI; §6 + §4 (B) reduce regression risk; §5 + §10 (C) improve batch UX; §9 + §11 (D) team outputs; §12 + §14 + §15 (E) human workflow.

---

## Competitive snapshot (MD-focused)

| Capability | md-translator (browser) | rosetta-mark (VS Code) | i18n-translator-sync | **This project (target)** |
|------------|-------------------------|------------------------|----------------------|---------------------------|
| Preserve code/fences | ✓ | ✓ | ✓ | ✓ MVP |
| Glossary | ? | ✓ | via TM/CSV | §1 |
| Translation memory | IndexedDB cache | Hash cache dir | SQLite + CSV | §2 |
| CLI / watch | Browser | Extension | ✓ watch/sync | §3, §15 |
| Live preview | ✓ | Split view | — | §4 |
| Batch progress | — | Streaming | — | §5 |
| Multi-engine | AI providers | Multi-provider | Azure/DeepL/Gemini | OpenAI + DeepL |

**Positioning recommendation:** Own **«Markdown + technical docs + web + API + CLI»** with **glossary + TM + validator** — match rosetta-mark/i18n-sync on consistency, beat generic browser translators on **batch API + shell comments + dual provider**.

---

## MVP recommendation (post–brownfield)

**Already shipped (do not re-prioritize):** segmentation, code preservation, three UI modes, REST API, batch ZIP, OpenAI/DeepL, retries.

**Prioritize next (NOTEBOOK Phase A — aligns table stakes for target users):**

1. **Glosario (§1)** — unlocks terminology for tech docs  
2. **Memoria de traducción (§2)** — cost + consistency in large batches  
3. **CLI real (§3)** — CI/automation table stake  

**Then Phase B for trust:**

4. **Validación post-traducción (§6)**  
5. **Vista previa renderizada (§4)**  

**Defer until later phases:**

- **§9 Multi-destino**, **§11 Docker** — Phase D (team)  
- **§12 Revisión**, **§15 Watch**, **§14 Diff** — Phase E (editorial)  
- **§19 HTML/PDF**, **§20 multi-tenant** — optional / out of scope  

**Quick win candidate:** **§13 Fallback** — low effort, improves reliability (could move before Phase E).

---

## Sources

| Source | Used for | Confidence |
|--------|----------|------------|
| `.planning/PROJECT.md` | Validated vs Active requirements, out of scope | HIGH |
| `NOTEBOOK.md` | Full §1–§20 map, phases A→E | HIGH |
| `.planning/codebase/INTEGRATIONS.md` | Current API surface, no TM/cache/auth | HIGH |
| `README.md` | MVP feature list | HIGH |
| [OpenL — translate technical docs without breaking code](https://blog.openl.io/how-to-translate-technical-docs-without-breaking-code/) | Table stakes: DNT list, fences, validation | MEDIUM |
| [Lara — localize developer documentation in Markdown](https://blog.laratranslate.com/how-to-localize-developer-documentation-in-markdown/) | Table stakes: code/CLI/API paths, glossary | MEDIUM |
| [MetalGlot — Markdown localization](https://metalglot.com/blog/markdown/) | Table stakes: frontmatter keys, link URLs | MEDIUM |
| [rockbenben/md-translator](https://github.com/rockbenben/md-translator) | Differentiators: cache, multi-lang, context mode | MEDIUM |
| [seewhyme/rosetta-mark](https://github.com/seewhyme/rosetta-mark) | Differentiators: glossary, incremental cache, streaming | MEDIUM |
| [appsitu-com/i18n-translator-sync](https://github.com/appsitu-com/i18n-translator-sync) | TM, watch/sync, CSV TM export | MEDIUM |
| [glossboss-labs/glossboss](https://github.com/glossboss-labs/glossboss) | TM + QA patterns (non-MD, analog) | LOW for MD-specific |
