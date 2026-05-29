# Phase 6 Context — v1 Tech Debt Closure

**Milestone:** v2.0 Production Polish & PDF  
**Source:** Audit v1.0 (`STATE.md` deferred items), `REQUIREMENTS.md` DEBT-01…04  
**Type:** Brownfield closure — no new features, parity and documentation gaps

## Problem

v1.0 shipped with four peripheral gaps:

1. **DEBT-01** — `batch --zip` omits `tone` in `_build_options` (line ~296) while dir/output-dir paths pass it.
2. **DEBT-02** — `API_TOKEN` + `verify_api_token` exist server-side; UI never sends `Authorization` and SSE `/events` is unauthenticated.
3. **DEBT-03** — Editor multi-target API returns `translations` map but UI only surfaces `targetLangs[0]` for preview/output/download.
4. **DEBT-04** — Phase 2 lacks `02-VERIFICATION.md` (other phases 0–1, 3–5 have one).

## Decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| D-01 | SSE auth via query param `access_token` on events endpoint | EventSource cannot set custom headers; same token as Bearer |
| D-02 | Token stored in `localStorage` key `md-translate-api-token` | Opt-in, no secrets in repo; user pastes when deploying with `API_TOKEN` |
| D-03 | Editor lang switcher = horizontal tabs above output | Reuse chip/tab visual language from target-lang chips (phase 4) |
| D-04 | Retroactive `02-VERIFICATION.md` status `passed` | Phase 2 executed and tested; doc is audit artifact only |
| D-05 | Regression tests in plan 06-04, not blocking 06-01–03 | Keeps wave 1–2 fast; 06-04 consolidates test coverage |

## Out of scope

- PDF export (phase 7)
- New translation providers or parser rules
- Server-side session store for tokens
- Auto-detect `API_TOKEN` requirement (401 handler prompts user is enough)

## Success (from ROADMAP)

1. `md-translate batch --zip -t es --tone formal` applies tone
2. UI Bearer + SSE work with `API_TOKEN` set
3. Editor shows/downloads each language when 2+ targets
4. `02-VERIFICATION.md` exists with passed status
