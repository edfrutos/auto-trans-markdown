---
phase: 00-mvp-hardening
plan: 03
subsystem: api
tags: [i18n, deepl, openai, ui]
requires:
  - phase: 00-01
  - phase: 00-02
provides:
  - get_supported_language_codes / is_valid_* helpers
  - _validate_languages en todas las rutas
  - UI dinámica desde /api/languages
affects: [phase-1-pipeline, phase-4-docker]
tech-stack:
  added: []
  patterns: [provider-scoped language lists]
key-files:
  modified: [src/translator.py, src/main.py, static/index.html, static/js/app.js]
requirements-completed: [HARD-03]
duration: 15min
completed: 2026-05-28
---

# Phase 0 Plan 03 Summary

**Idiomas filtrados por TRANSLATION_PROVIDER; validación source/target en JSON y multipart; UI sin listas hardcodeadas.**

## Accomplishments
- Helpers de idioma por proveedor en traductor
- `/api/languages` y `_validate_languages` unificados
- Selects de UI cargados dinámicamente con manejo de error
