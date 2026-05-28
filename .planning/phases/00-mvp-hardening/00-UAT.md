---
status: complete
phase: 00-mvp-hardening
source: 00-01-SUMMARY.md, 00-02-SUMMARY.md, 00-03-SUMMARY.md, 00-04-SUMMARY.md
started: 2026-05-28T18:00:00Z
updated: 2026-05-28T18:05:00Z
verification_mode: automated
---

## Current Test

[testing complete]

## Tests

### 1. Traducción incompleta → error explícito (HARD-01)
expected: Si el proveedor devuelve menos segmentos, la API responde HTTP 502 con mensaje que indica cuántos faltan; nunca se entrega Markdown parcial como éxito.
result: pass
verified: automated — pytest test_translate_incomplete_returns_502, test_openai_incomplete_raises, smoke TestClient

### 2. Upload no UTF-8 → HTTP 400 (HARD-02)
expected: Subir bytes inválidos en archivo único o lote devuelve 400 con mensaje que menciona UTF-8; no hay sustitución silenciosa de caracteres.
result: pass
verified: automated — pytest test_decode_upload_invalid_utf8_raises, test_translate_file/batch invalid utf8; rg confirma ausencia de latin-1 en main.py

### 3. Idiomas filtrados por proveedor en API (HARD-03)
expected: GET /api/languages con DeepL activo no incluye catalán (ca) pero sí español (es); POST con target_lang inválido → 400 en JSON y multipart.
result: pass
verified: automated — pytest test_languages_deepl_excludes_ca, test_translate_invalid_target_lang_deepl, test_translate_file/batch invalid lang

### 4. UI carga idiomas desde API (HARD-03)
expected: Los selects de idioma se pueblan desde /api/languages; index.html no tiene lista hardcodeada de destinos; app.js no define arrays estáticos de idiomas.
result: pass
verified: automated — static/index.html sin option value="es" hardcodeado; app.js fetch /api/languages; loadLanguages sin fallback estático

### 5. Suite de integración sin API keys (HARD-04)
expected: pytest tests/ pasa (30 tests) cubriendo traductor mockeado, API TestClient, round-trip segment→translate→reassemble y parser existente.
result: pass
verified: automated — pytest tests/ -q → 30 passed

### 6. Cold Start Smoke Test
expected: La aplicación arranca sin errores de import; TestClient responde en /api/languages; pytest collect encuentra todos los tests.
result: pass
verified: automated — import src.main OK; TestClient GET /api/languages → 200; pytest --collect-only tests/

## Summary

total: 6
passed: 6
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none]
