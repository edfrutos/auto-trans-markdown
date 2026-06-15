---
phase: 00-mvp-hardening
plan: 02
subsystem: api
tags: [utf-8, validation, uploads]
requires:

  - phase: 00-01
    provides: error handling patterns

provides:

  - _decode_upload UTF-8 estricto
  - tests API para uploads inválidos

affects: [phase-1-cli]
tech-stack:
  added: []
  patterns: [reject invalid bytes with HTTP 400]
key-files:
  created: [tests/test_api.py]
  modified: [src/main.py]
requirements-completed: [HARD-02]
duration: 10min
completed: 2026-05-28
---

# Phase 0 Plan 02 Summary

**Uploads no UTF-8 rechazados con HTTP 400; eliminado fallback latin-1/replace.**

## Accomplishments

- `_decode_upload` solo acepta UTF-8 válido
- Mensaje de error accionable en español
- Tests para file y batch con bytes inválidos
