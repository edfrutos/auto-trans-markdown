---
status: complete
phase: 01-production-table-stakes
source: 01-01-SUMMARY.md, 01-02-SUMMARY.md, 01-03-SUMMARY.md, 01-04-SUMMARY.md, 01-05-SUMMARY.md
started: 2026-05-28T20:00:00Z
updated: 2026-05-28T22:00:00Z
completed: 2026-05-28T22:00:00Z
---

## Current Test

[none — UAT complete]

## Tests

### 1. Cold Start Smoke Test
expected: Detén el servidor si está en marcha. Ejecuta `pip install -e .` si aún no lo hiciste. Arranca con `md-translate serve` o `python -m src.main`. Abre http://127.0.0.1:8000 — la página carga, los idiomas destino dejan de decir «Cargando…» y aparece el panel «Glosario» colapsado bajo los selectores de idioma.
result: pass
note: Re-test tras fix caché; glosario visible, sin error innerHTML

### 2. Traducción en editor (pipeline unificado)
expected: En la pestaña Editor, carga el ejemplo y pulsa Traducir. Recibes Markdown traducido en el panel derecho, mensaje de éxito con recuento de segmentos, y botón Descargar habilitado — mismo comportamiento que antes de la fase 1.
result: pass

### 3. Panel glosario — cargar y guardar
expected: Expande «Glosario», añade una fila (término + traducción o «No traducir»), pulsa «Guardar glosario». Ves mensaje de éxito; al recargar la página la entrada sigue visible.
result: pass

### 4. Glosario aplicado en traducción
expected: Con par origen→destino configurado (p. ej. en→es), guarda en glosario que «dashboard» → «panel». Traduce un texto que contenga «dashboard» en el editor: la salida usa «panel» (o el término fijado), no una traducción libre del modelo.
result: pass

### 5. Memoria de traducción (cache)
expected: Traduce el mismo párrafo dos veces seguidas en el editor (mismo idioma). La segunda traducción completa correctamente con el mismo resultado; no hay error 502 ni contenido vacío.
result: pass

### 6. Limpiar memoria desde la web
expected: Pulsa «Limpiar memoria», confirma el diálogo. Aparece mensaje de éxito («Memoria de traducción vaciada» o similar).
result: pass

### 7. Traducción de archivo único
expected: En pestaña Archivo, sube un .md y traduce. Descargas el archivo traducido con sufijo de idioma (p. ej. `.es.md`).
result: pass

### 8. CLI — ayuda y dry-run
expected: En terminal: `md-translate --help` lista subcomandos file, dir, batch, serve, memory. `md-translate file README.md -t es --dry-run` imprime líneas JSON con índice y texto de segmentos, sin crear archivo de salida.
result: pass
note: pip install -e . + scripts/md-translate para uso sin activar venv

### 9. CLI — traducir archivo
expected: `md-translate file README.md -t es -o /tmp/README.es.md` crea el archivo de salida con contenido traducido (requiere API key configurada).
result: pass
note: PATH en ~/.zshrc + source ~/.zshrc; scripts/md-translate

## Summary

total: 9
passed: 9
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none]
