---
phase: 00-mvp-hardening
plan: 04
subsystem: testing
tags: [pytest, integration, mocks]
requires:
  - phase: 00-01
  - phase: 00-02
  - phase: 00-03
provides:
  - Suite pytest completa sin API keys
  - conftest con fixtures TestClient y mocks
affects: [phase-1-pipeline]
tech-stack:
  added: [pytest>=8.0]
  patterns: [mock translate_segments at API boundary]
key-files:
  created: [tests/conftest.py, tests/test_integration.py]
  modified: [tests/test_translator.py, tests/test_api.py, pyproject.toml]
requirements-completed: [HARD-04]
duration: 15min
completed: 2026-05-28
---

# Phase 0 Plan 04 Summary

**30 tests pasan sin credenciales: traductor, API, integración pipeline y parser existente.**

## Accomplishments
- `tests/conftest.py` con fixtures compartidas
- Casos D-11: 502 incompleto, 400 UTF-8, 400 idioma inválido, round-trip reassemble
- `pytest` en optional-dependencies test
