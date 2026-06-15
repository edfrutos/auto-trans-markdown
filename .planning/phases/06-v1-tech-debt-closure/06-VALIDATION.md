---
phase: 6
slug: v1-tech-debt-closure
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-29
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property               | Value                                                                    |
| ---------------------- | ------------------------------------------------------------------------ |
| **Framework**          | pytest (pyproject.toml testpaths = tests)                                |
| **Config file**        | pyproject.toml `[tool.pytest.ini_options]`                               |
| **Quick run command**  | `pytest tests/test_cli.py tests/test_deployment.py tests/test_api.py -q` |
| **Full suite command** | `pytest tests/ -q`                                                       |
| **Estimated runtime**  | ~25 seconds                                                              |

---

## Sampling Rate

- **After every task commit:** Run quick run command for touched modules
- **After every plan wave:** Run `pytest tests/ -q`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID   | Plan   | Wave   | Requirement   | Test Type   | Automated Command                                                                          | Status    |
| --------- | ------ | ------ | ------------- | ----------- | ------------------------------------------------------------------------------------------ | --------- |
| 06-01-01  | 01     | 1      | DEBT-01       | unit        | `pytest tests/test_cli.py -q -k batch_zip_tone`                                            | ⬜ pending |
| 06-02-01  | 02     | 1      | DEBT-02       | unit        | `pytest tests/test_deployment.py tests/test_api.py -q -k api_token`                        | ⬜ pending |
| 06-02-02  | 02     | 1      | DEBT-02       | integration | `pytest tests/test_api.py -q -k batch_job_events`                                          | ⬜ pending |
| 06-03-01  | 03     | 2      | DEBT-03       | static      | `grep -q translationResults static/js/app.js && grep -q activeResultLang static/js/app.js` | ⬜ pending |
| 06-03-02  | 03     | 2      | DEBT-03       | manual      | Editor 2 langs → switch tab → download each                                                | ⬜ pending |
| 06-04-01  | 04     | 3      | DEBT-04       | doc         | `test -f .planning/phases/02-trust-qa/02-VERIFICATION.md`                                  | ⬜ pending |
| 06-04-02  | 04     | 3      | DEBT-01–03    | unit        | `pytest tests/ -q`                                                                         | ⬜ pending |

---

## Manual-Only Verifications

| Behavior          | Requirement   | Test Instructions                                                        |
| ----------------- | ------------- | ------------------------------------------------------------------------ |
| UI token settings | DEBT-02       | Set `API_TOKEN` in `.env`; paste token in UI; translate editor succeeds  |
| SSE with token    | DEBT-02       | Batch job with token — progress events stream (no 401)                   |
| Multi-lang tabs   | DEBT-03       | Select es+en; translate; switch tabs; preview/validation update per lang |

---

## Validation Sign-Off

- [x] All tasks have automated verify or manual map entry
- [x] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
