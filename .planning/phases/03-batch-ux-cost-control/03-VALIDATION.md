---
phase: 3
slug: batch-ux-cost-control
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-05-29
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest (pyproject.toml testpaths = tests) |
| **Config file** | pyproject.toml `[tool.pytest.ini_options]` |
| **Quick run command** | `pytest tests/test_estimate.py tests/test_batch_zip.py tests/test_jobs.py -q` |
| **Full suite command** | `pytest tests/ -q` |
| **Estimated runtime** | ~20 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command for touched modules
- **After every plan wave:** Run `pytest tests/ -q`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 25 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 03-01-01 | 01 | 1 | COST-01 | unit | `pytest tests/test_estimate.py -q` | ⬜ pending |
| 03-02-01 | 02 | 1 | JOB-04 | unit | `pytest tests/test_batch_zip.py -q` | ⬜ pending |
| 03-02-02 | 02 | 1 | JOB-01 | unit | `pytest tests/test_jobs.py -q` | ⬜ pending |
| 03-02-03 | 02 | 1 | JOB-03 | unit | `pytest tests/test_jobs.py -q -k cancel` | ⬜ pending |
| 03-03-01 | 03 | 2 | JOB-02 | integration | `pytest tests/test_api.py -q -k batch_job` | ⬜ pending |
| 03-03-02 | 03 | 2 | COST-02 | manual | Estimate visible batch/file UI | ⬜ pending |
| 03-04-01 | 04 | 3 | JOB-01 | integration | `pytest tests/test_api.py -q -k batch_job` | ⬜ pending |

---

## Manual-Only Verifications

| Behavior | Requirement | Test Instructions |
|----------|-------------|-------------------|
| Batch progress bar + file list | JOB-02 | Upload 3 files; start batch; verify list states update |
| Cancel with confirm | JOB-03 | Cancel mid-job; confirm dialog; partial download offered |
| Estimate threshold banner | COST-02 | Set low ESTIMATE_WARN_USD; verify amber warning |
| Mobile stacked layout | D-04 | Narrow viewport; progress section vertical |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or manual map entry
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
