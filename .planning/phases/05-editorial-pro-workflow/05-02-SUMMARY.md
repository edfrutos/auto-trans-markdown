# 05-02 Summary

**Plan:** Tono formal/informal API/CLI/UI (TONE-01)

## Entregado

- `tone` en `TranslateOptions`, `translate_segments`, DeepL `formality` y hint OpenAI
- API: `tone` en JSON/form; jobs batch propagan tono
- CLI: `--tone auto|formal|informal` en file/dir/batch/watch
- UI: selector `#tone-select` wired en `app.js`

## Verificación

`pytest tests/test_translator.py -q -k tone` — passed  
`pytest tests/test_api.py -q -k tone` — passed
