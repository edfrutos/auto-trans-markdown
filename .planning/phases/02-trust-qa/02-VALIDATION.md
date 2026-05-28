---
phase: 2
slug: trust-qa
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-05-28
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest (pyproject.toml testpaths = tests) |
| **Config file** | pyproject.toml `[tool.pytest.ini_options]` |
| **Quick run command** | `pytest tests/test_validator.py tests/test_parser.py -q` |
| **Full suite command** | `pytest tests/ -q` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command for touched modules
- **After every plan wave:** Run `pytest tests/ -q`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 20 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | VAL-01 | — | N/A | unit | `pytest tests/test_validator.py -q` | ✅ | ⬜ pending |
| 02-01-02 | 01 | 1 | VAL-01 | — | N/A | unit | `pytest tests/test_validator.py -q` | ✅ | ⬜ pending |
| 02-02-01 | 02 | 1 | PARS-01 | — | N/A | unit | `pytest tests/test_parser.py -q -k comment` | ✅ | ⬜ pending |
| 02-02-02 | 02 | 1 | FM-01 | — | N/A | unit | `pytest tests/test_parser.py -q -k frontmatter` | ✅ | ⬜ pending |
| 02-03-01 | 03 | 2 | VAL-02 | T-02-01 | validation in API JSON | integration | `pytest tests/test_api.py tests/test_pipeline.py -q` | ✅ | ⬜ pending |
| 02-03-02 | 03 | 2 | VAL-02 | — | validation.json in ZIP | integration | `pytest tests/test_api.py -q -k batch` | ✅ | ⬜ pending |
| 02-04-01 | 04 | 2 | VAL-03 | — | strict exit 1 | unit | `pytest tests/test_cli.py -q -k strict` | ✅ | ⬜ pending |
| 02-05-01 | 05 | 3 | PREV-01 | — | N/A | manual | UI preview renders | — | ⬜ pending |
| 02-05-02 | 05 | 3 | PREV-02 | T-02-02 | DOMPurify before innerHTML | manual | XSS fixture inert | — | ⬜ pending |
| 02-05-03 | 05 | 3 | VAL-02 | — | panel shows checks | manual | validation panel visible | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements — no new conftest needed.

- [x] `tests/test_parser.py` — extend for PARS/FM
- [x] `tests/test_pipeline.py`, `tests/test_api.py`, `tests/test_cli.py` — extend

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Preview dark mode | PREV-01 | Visual CSS | Toggle theme; verify prose-preview contrast |
| DOMPurify XSS | PREV-02 | Browser DOM | Translate doc with `[x](javascript:alert(1))`; no alert |
| Validation panel UX | VAL-02 | DOM layout | Translate; expand panel; icons match status |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or manual map entry
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 20s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
