---
phase: 00-mvp-hardening
plan: 01
subsystem: api
tags: [translation, error-handling, openai, deepl]
requires: []
provides:

  - IncompleteTranslationError con validación post-lote
  - HTTP 502 estructurado en endpoints translate_*

affects: [phase-1-pipeline]
tech-stack:
  added: []
  patterns: [fail-fast antes de reassemble]
key-files:
  created: [tests/test_translator.py]
  modified: [src/translator.py, src/main.py]
requirements-completed: [HARD-01]
duration: 15min
completed: 2026-05-28
---

# Phase 0 Plan 01 Summary

**Traducciones incompletas fallan con IncompleteTranslationError y HTTP 502 explícito — sin salida parcial silenciosa.**

## Accomplishments

- `IncompleteTranslationError` y `_validate_translation_completeness` en traductor
- Validación de longitud en respuestas DeepL
- Mapeo a HTTP 502 con `detail.message`, `expected`, `received`, `missing_indices`
- Tests unitarios del traductor para incompletitud OpenAI
