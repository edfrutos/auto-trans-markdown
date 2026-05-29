# 05-01 Summary

**Plan:** Fallback DeepL → OpenAI (FALL-01)

## Entregado

- `get_fallback_provider()`, `_translate_batch_with_fallback()` en `src/translator.py`
- `TRANSLATION_FALLBACK=openai` en `.env.example`
- `TranslateResult.provider_used` / `TranslateResponse.provider_used`
- Tests fallback en `tests/test_translator.py`

## Verificación

`pytest tests/test_translator.py -q -k fallback` — 3 passed
