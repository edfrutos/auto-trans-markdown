---
phase: 4
slug: team-scale
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-05-29
---

# Phase 4 — Validation Strategy

## Test Infrastructure

| Property               | Value                                                           |
| ---------------------- | --------------------------------------------------------------- |
| **Framework**          | pytest                                                          |
| **Quick run command**  | `pytest tests/test_target_langs.py tests/test_deployment.py -q` |
| **Full suite command** | `pytest tests/ -q`                                              |
| **Estimated runtime**  | ~25 seconds                                                     |

## Sampling Rate

- **After every task commit:** Quick run for touched modules
- **After every plan wave:** Full suite
- **Before verify-work:** Full suite green

## Per-Task Verification Map

| Task ID   | Plan   | Wave   | Requirement   | Test Type   | Automated Command                              | Status    |
| --------- | ------ | ------ | ------------- | ----------- | ---------------------------------------------- | --------- |
| 04-01-01  | 01     | 1      | MULTI-02      | unit        | `pytest tests/test_target_langs.py -q`         | ⬜ pending |
| 04-01-02  | 01     | 1      | MULTI-02      | unit        | `pytest tests/test_jobs.py -q -k multi`        | ⬜ pending |
| 04-01-03  | 01     | 1      | MULTI-01      | integration | `pytest tests/test_api.py -q -k multi`         | ⬜ pending |
| 04-02-01  | 02     | 1      | SEC-01        | unit        | `pytest tests/test_deployment.py -q -k cors`   | ⬜ pending |
| 04-02-02  | 02     | 1      | SEC-02        | unit        | `pytest tests/test_deployment.py -q -k upload` | ⬜ pending |
| 04-03-01  | 03     | 2      | MULTI-01      | manual      | Chips + nested progress UI                     | ⬜ pending |
| 04-04-01  | 04     | 2      | MULTI-01      | unit        | `pytest tests/test_cli.py -q -k multi`         | ⬜ pending |
| 04-05-01  | 05     | 3      | DOCKER-01     | manual      | `docker build -t md-translate .`               | ⬜ pending |
| 04-05-02  | 05     | 3      | DOCKER-02     | manual      | `docker compose config`                        | ⬜ pending |

## Manual-Only Verifications

| Behavior             | Requirement   | Test Instructions                                   |
| -------------------- | ------------- | --------------------------------------------------- |
| Multi-lang batch ZIP | MULTI-02      | Select es+en; download ZIP; verify both suffixes    |
| CORS blocked origin  | SEC-01        | Set CORS_ORIGINS; fetch from wrong origin → blocked |
| Docker healthcheck   | DOCKER-02     | `docker compose up`; wait healthy                   |

## Validation Sign-Off

- [ ] All tasks have automated verify or manual map entry
- [ ] Wave 0 covers all MISSING references
