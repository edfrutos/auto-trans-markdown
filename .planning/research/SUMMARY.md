# Project Research Summary

**Project:** MarkDown Auto Translator — NOTEBOOK milestone (A→E)  
**Domain:** Local-first Markdown / technical documentation translation (segment → translate → reassemble)  
**Researched:** 2026-05-28  
**Confidence:** HIGH overall for stack and architecture; MEDIUM for competitive feature ranking and SSE job-store details

## Executive Summary

MarkDown Auto Translator is a **brownfield extension** of an existing Python/FastAPI/vanilla-JS monolith that already delivers the core MD translation pipeline (protected segmentation, dual providers, web UI, REST API, batch ZIP). The MVP covers most **format-safe translation table stakes**; the NOTEBOOK milestone closes production gaps (glossary, translation memory, CLI, validation, real progress) and then scales toward team deployment and editorial workflow (Docker, multi-target, review, watch).

Experts build tools in this space as **deterministic segment-and-translate pipelines**, not as plain-text MT. The recommended approach is to **extend in place**: add Typer CLI, stdlib SQLite TM, YAML glossary, a single `pipeline.py` orchestration facade, stdlib validator, FastAPI 0.135+ SSE, and CDN-only preview (marked + DOMPurify). Do **not** introduce a frontend bundler, ORM, or Redis for this milestone. Close the `uv.lock` gap early for reproducible Docker builds in Phase D.

The dominant risks are **structural breakage** (fences, links, frontmatter, silent partial translations) and **operational exposure** (batch all-or-nothing, fake progress, unauthenticated deploy). Mitigation: extract `translate_markdown()` before new features; enforce segment-count validation and optional strict mode; build validator + preview in Phase B before Docker; harden auth/limits before Phase D public images.

## Key Findings

### Recommended Stack

Extend the current stack without architectural churn. Bump FastAPI to ≥0.135 for native SSE; add Typer (not Click) for CLI; use stdlib `sqlite3` (WAL) for TM and PyYAML for glossary; keep frontend CDN-only with **marked + DOMPurify mandatory** for preview; add `uv.lock` + multi-stage Docker (python:3.12-slim-bookworm, not Alpine). Blocking I/O continues via `run_in_executor`; SSE uses in-memory `asyncio.Queue` per job — acceptable for single-process local deploy.

**Core technologies:**

- **Python 3.11+ / FastAPI ≥0.135 / Uvicorn:** Keep ASGI monolith; SSE via `EventSourceResponse` without hand-rolled framing
- **Typer ≥0.21:** `md-translate` CLI with subcommands (`file`, `dir`, `batch`, `serve`); entry point must change from `src.main:run` to `src.cli:app`
- **sqlite3 (stdlib):** TM at `data/translation_memory.db`; hash key `sha256(normalize(text)+source+target)`; zero extra deps
- **PyYAML ≥6.0.2:** `glossary.yaml` + selective frontmatter allowlist; `safe_load`/`safe_dump` only
- **uv + uv.lock:** Primary lockfile; export `requirements.txt` for pip fallback; Docker multi-stage with non-root runtime
- **marked + DOMPurify (CDN):** Client preview only; sanitize hook non-negotiable
- **watchdog ≥6.0 (Phase E):** Folder watch as CLI subcommand, not web server thread

**Defer:** WeasyPrint/Pandoc (PDF), tiktoken (cost accuracy), SQLCipher, Redis (until multi-worker scaling is real).

### Expected Features

MVP already validates segmentation, code/fence preservation, three UI modes, REST API, batch ZIP (max 20), OpenAI + DeepL, retries. Remaining **table-stake gaps** for tech-doc teams: glossary/DNT list, TM consistency across batches, real CLI for CI, post-translation validation, real batch progress.

**Must have (table stakes — close in Phase A–B):**

- **Protected segmentation + reassemble** — already shipped; do not regress
- **Glossary / fixed terms (§1)** — terminology lock expected by CAT and MD tools
- **Translation memory (§2)** — repeated strings, cost, consistency across repo
- **CLI `md-translate` (§3)** — CI/automation without web server
- **Post-translation validation (§6)** — catch silent structure breaks before merge
- **Real batch progress (§5)** — long jobs without feedback feel broken

**Should have (differentiators — Phases B–D):**

- **Rendered MD preview + sanitization (§4)** — visual QA for tables/lists
- **SSE progress + cost estimate (§5, §10)** — trust and budget control on large batches
- **Multi-target one pass (§9) + Docker (§11)** — team scale and one-command deploy
- **Provider fallback (§13)** — low effort, high reliability; candidate to pull forward

**Defer (v2+ / Phase E):**

- Review mode (§12), folder watch (§15), visual diff (§14), docs-site tree (§16), HTML/PDF export (§19), multi-tenant API keys (§20 — anti-feature this milestone)

**Anti-features (explicitly avoid):** PDF/DOCX in-place, offline MT as primary engine, IDE plugins, free-form rewriting, translating YAML keys/URLs/code, public deploy with CORS `*` and no auth.

### Architecture Approach

**Do not embed glossary, memory, or validation in `parser.py`.** Parser stays pure (string in → segments out). Introduce **`src/pipeline.py`** as the single orchestration facade that today is duplicated in `_translate_file_content()` and HTTP handlers. API, CLI, and SSE jobs all call `translate_markdown(content, TranslateOptions)`; `translator.translate_segments()` receives optional hooks but knows nothing about HTTP, ZIP, or SSE.

**Major components:**

1. **`pipeline.py`** — Orchestrates parser → memory.partition → glossary pre/post → translator → memory.store → reassemble → optional validator
2. **`memory.py`** — SQLite lookup/store keyed on **pre-glossary** segment text; WAL mode
3. **`glossary.py`** — YAML rules; OpenAI prompt injection + DeepL placeholder wrap/restore
4. **`validator.py`** — Post-`reassemble` structural checks (fences, links, headings); warnings by default, `--strict` to block
5. **`cli.py` / `jobs.py`** — Thin entry surfaces; jobs registry + SSE without reimplementing translation

**Build order (technical, refines NOTEBOOK A→C):** (1) pipeline refactor → (2) memory → (3) glossary → (4) CLI → (5) validator → (6) jobs/SSE. Preview, multi-target, Docker, frontmatter selective follow without blocking this slice.

### Critical Pitfalls

1. **Treating `.md` as plain text** — Never skip parse → translate TRANSLATABLE only → reassemble; add validator in Phase B
2. **Chunk/placeholder desync (fences, lists)** — Keep segments atomic in chunking; validator counts fences; tests for orphan fences and indented lists
3. **Silent untranslated segments in `reassemble`** — Enforce `len(translations) == len(collect_translatable)` or fail with `complete: false`; Pre-A hardening
4. **Frontmatter all-or-nothing** — Whitelist translatable fields (§8); never translate YAML keys; fallback to full block protect on invalid YAML
5. **Broken internal links/anchors after heading translation** — Protect URL in link segments; optional slug reconciliation in validator (critical before multi-target Phase D)
6. **Unstable OpenAI JSON batch responses** — Strict cardinality validation; consider function-calling with fixed properties; tests with malformed fixtures
7. **No glossary/TM** — Phase A deliverables; glossary increases prompt size and pressure on JSON (#6)
8. **Exposed API without auth/limits** — Mandatory before Docker/team deploy (Phase D); default `127.0.0.1`, upload caps, rate limits
9. **Batch all-or-nothing on first failure** — Partial ZIP + `errors.json` or async jobs with per-file state (Phase C)
10. **Language list vs provider capability mismatch** — Filter `/api/languages` by provider; validate `target_lang` on all routes including CLI

## Implications for Roadmap

Based on combined research, adopt NOTEBOOK phases A→E with a **Pre-A hardening slice** and **pipeline-first** technical ordering inside Phase A.

### Pre-A: MVP Hardening (recommended before or concurrent with Phase A start)
**Rationale:** PITFALLS research flags silent partial translations, JSON batch failures, and provider/language mismatch as active bugs (`CONCERNS.md`); fixing these prevents building glossary/TM on a leaky foundation.  
**Delivers:** Segment-count contract tests, `tests/test_translator.py` + `tests/test_main.py`, strict UTF-8 decode, provider-aware language validation.  
**Addresses:** Translation completeness, API contract quality.  
**Avoids:** Pitfalls #3, #6, #10, #12.

### Phase A: Production Table Stakes (NOTEBOOK §1–§3)
**Rationale:** Features research and competitive positioning agree glossary + TM + CLI unlock CI and terminology consistency; architecture requires `pipeline.py` first.  
**Delivers:** `pipeline.py`, `memory.py`, `glossary.py`, `cli.py` (Typer), `uv.lock` + deps (Typer, PyYAML, pydantic-settings, FastAPI bump), fix `md-translate` entry point.  
**Addresses:** §1 Glossary, §2 TM, §3 CLI.  
**Uses:** sqlite3, PyYAML, Typer, executor pattern.  
**Avoids:** Pitfalls #7, #18; anti-pattern of glossary inside parser.  
**Internal build order:** pipeline → memory → glossary → CLI.

### Phase B: Trust & QA (NOTEBOOK §4, §6, §7–§8 stretch)
**Rationale:** Table-stake gap for post-translation checks; preview pairs with validator; frontmatter selective and comment languages extend parser only.  
**Delivers:** `validator.py`, preview UI (marked + DOMPurify), optional frontmatter whitelist, extended fence comment languages.  
**Addresses:** §6 Validation, §4 Preview, §7–§8 extensions.  
**Avoids:** Pitfalls #1, #2, #4, #5, #21 (XSS in preview).

### Phase C: Batch UX & Cost Control (NOTEBOOK §5, §10)
**Rationale:** Depends on stable pipeline with `on_progress` wired end-to-end; replaces simulated 30% progress and batch all-or-nothing UX.  
**Delivers:** `jobs.py`, SSE routes (`EventSourceResponse`), EventSource client, estimate endpoint (char-based initially), partial batch results.  
**Uses:** FastAPI ≥0.135 SSE, in-memory job registry, existing `on_progress` in translator.  
**Avoids:** Pitfalls #9, #13, #14; anti-pattern of SSE reimplementing translation.

### Phase D: Team Scale (NOTEBOOK §9, §11)
**Rationale:** Multi-target and Docker assume TM, validator, and auth hardening; deploying without #8/#16 is a common MD-i18n failure mode.  
**Delivers:** Multi-target API, Dockerfile + compose (uv, slim base, volumes for `data/` and `output/`), upload/TTL limits, bind/auth guidance.  
**Addresses:** §9 Multi-target, §11 Docker.  
**Avoids:** Pitfalls #5 (at scale), #8, #16.

### Phase E: Editorial / Pro Workflow (NOTEBOOK §12–§19)
**Rationale:** High-effort differentiators after core pipeline and deploy are stable; watch/diff/review need segment-level APIs.  
**Delivers:** Review mode, visual diff, folder watch (watchdog CLI), provider fallback (§13), formality (§17), optional HTML/PDF.  
**Avoids:** Pitfall #3 drift in watch mode; keep watch as CLI not web thread.

### Phase Ordering Rationale

- **Pipeline facade first** — All four research streams converge: without `translate_markdown()`, glossary/TM/CLI/SSE will diverge (architecture anti-patterns #1–#3).
- **A before B** — Terminology and automation are table stakes; validation catches regressions from glossary prompt growth.
- **B before D** — Link/anchor and fence checks must be reliable before multi-locale site trees and Docker exposure.
- **C before D** — Batch resilience and progress reduce support burden when teams deploy.
- **Auth/limits before Docker** — PITFALLS explicitly warns against shipping images before hardening (#8).

### Research Flags

Phases likely needing `/gsd-research-phase` during planning:

- **Phase B:** Anchor/slug reconciliation and frontmatter selective parsing — sparse single-pattern docs; may need spike on GitHub-slug rules
- **Phase C:** SSE job lifecycle (cancel, disconnect cleanup, partial ZIP) — MEDIUM confidence patterns, not yet in repo
- **Phase D:** Multi-target concurrency + rate limits × N languages — integration research on shared TM keys
- **Phase E:** Watch debounce + review segment state — filesystem edge cases

Phases with standard patterns (skip deep research):

- **Phase A:** Typer CLI, SQLite TM, YAML glossary — well-documented, stack research HIGH confidence
- **Phase A (pipeline refactor):** Facade/orchestration — codebase-specific but pattern is established in ARCHITECTURE.md
- **Phase B (validator v1):** Regex/count checks — stdlib-only, NOTEBOOK §6 scope clear

## Confidence Assessment

| Area         | Confidence                                            | Notes                                                                                                   |
| ------------ | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Stack        | HIGH                                                  | Official FastAPI SSE, Typer, uv Docker docs; brownfield baseline verified                               |
| Features     | HIGH (table stakes) / MEDIUM (differentiator ranking) | Codebase + NOTEBOOK + industry blogs; not formal market study                                           |
| Architecture | HIGH                                                  | Code audit of `main.py`, `parser.py`, `translator.py`; pipeline contract proposed with clear boundaries |
| Pitfalls     | HIGH                                                  | Repo `CONCERNS.md` + industry sources; phase mapping explicit                                           |

**Overall confidence:** HIGH

### Gaps to Address

- **Anchor/slug reconciliation:** Validator v1 can count links/URLs; full heading-slug rewrite needs spike in Phase B planning
- **OpenAI batch reliability vs glossary size:** Monitor parse failure rate after §1; may need function-calling migration mid-Phase A
- **SSE multi-worker:** In-memory job dict documented as single-process limitation; no Redis until scaling requirement is real
- **Cost estimate accuracy:** Start char/4 + static price table; tiktoken deferred until Phase C validation
- **Competitive positioning:** MEDIUM evidence only — validate with one user interview or dogfood batch before Phase D marketing

## Sources

### Primary (HIGH confidence)

- `.planning/PROJECT.md`, `NOTEBOOK.md` — scope, phases, requirements
- `.planning/codebase/CONCERNS.md`, `ARCHITECTURE.md` — brownfield debt and boundaries
- [FastAPI SSE tutorial](https://fastapi.tiangolo.com/tutorial/server-sent-events/) — EventSourceResponse
- [Typer packaging docs](https://github.com/fastapi/typer) — CLI entry points
- [uv Docker integration](https://docs.astral.sh/uv/guides/integration/docker/) — lockfile builds
- [marked.js security](https://marked.js.org/) — DOMPurify requirement
- [Azure AI glossaries](https://github.com/MicrosoftDocs/azure-ai-docs/blob/main/articles/ai-services/translator/document-translation/how-to-guides/create-use-glossaries.md)

### Secondary (MEDIUM confidence)

- FoundryL10n, TransDuck, rosetta-mark, i18n-translator-sync — local-first TM and MD tool patterns
- MetalGlot, Lara, OpenL blogs — MD localization table stakes
- [Azure Feeds MD pipeline hardening](https://azurefeeds.com/2026/04/30/fixing-broken-markdown-in-ai-translation-hardening-a-production-pipeline/) — chunking, atomic fences
- [GenAIScript continuous translations](https://microsoft.github.io/genaiscript/blog/continuous-translations/) — URL validation

### Tertiary (LOW confidence)

- glossboss-labs/glossboss — CAT patterns analog, not MD-specific

### Detailed research files

- `.planning/research/STACK.md`
- `.planning/research/FEATURES.md`
- `.planning/research/ARCHITECTURE.md`
- `.planning/research/PITFALLS.md`

---
*Research completed: 2026-05-28*  
*Ready for roadmap: yes*
