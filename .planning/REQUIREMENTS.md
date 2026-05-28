# Requirements — MarkDown Auto Translator (NOTEBOOK milestone)

**Defined:** 2026-05-28  
**Core value:** Traducir solo texto al usuario sin romper Markdown ni código, con coherencia y coste predecible.

## v1 Requirements

### Hardening (Pre-A)

- [x] **HARD-01**: El sistema rechaza traducciones incompletas cuando el número de segmentos traducidos no coincide con los solicitados
- [x] **HARD-02**: El usuario recibe error claro al subir archivos que no son UTF-8 válido (sin sustitución silenciosa)
- [x] **HARD-03**: La lista de idiomas expuesta refleja las capacidades del proveedor activo (OpenAI vs DeepL)
- [x] **HARD-04**: Existen tests de integración para `translate_segments`, endpoints API y contrato de reassemble

### Pipeline & Core (Phase A)

- [ ] **PIPE-01**: Existe `translate_markdown()` en `src/pipeline.py` como única fachada usada por API y CLI
- [ ] **GLOS-01**: El usuario puede definir glosario en `glossary.yaml` (no traducir, traducción fija por par de idiomas)
- [ ] **GLOS-02**: El usuario puede gestionar entradas del glosario desde la UI web
- [ ] **GLOS-03**: Glosario aplicado en editor, archivo único y lote
- [ ] **TM-01**: Segmentos traducidos se cachean en SQLite (`data/translation_memory.db`) por hash+idiomas
- [ ] **TM-02**: Cache consultada antes de llamar al proveedor; nuevas traducciones se persisten
- [ ] **TM-03**: El usuario puede limpiar la memoria de traducción (UI o CLI)
- [ ] **CLI-01**: Comando `md-translate file` traduce un `.md` a archivo de salida
- [ ] **CLI-02**: Comando `md-translate dir` traduce recursivamente un directorio preservando estructura
- [ ] **CLI-03**: Comando `md-translate batch` genera ZIP o directorio de salida
- [ ] **CLI-04**: Flag `--dry-run` lista segmentos traducibles sin llamar al proveedor
- [ ] **CLI-05**: Entry point `md-translate` apunta a CLI; servidor web tiene comando separado (`serve`)

### Trust & QA (Phase B)

- [ ] **VAL-01**: Validador post-traducción comprueba conteo de fences, enlaces e imágenes
- [ ] **VAL-02**: Informe de validación visible en UI y opcionalmente en ZIP de lote
- [ ] **VAL-03**: Modo `--strict` en CLI bloquea export si validación falla
- [ ] **PREV-01**: UI muestra vista previa renderizada del Markdown (original y traducido)
- [ ] **PREV-02**: Preview sanitiza HTML (DOMPurify) antes de renderizar
- [ ] **PARS-01**: Comentarios traducibles en fences Python (`#`) además de shell
- [ ] **PARS-02**: Comentarios traducibles en JS/TS (`//`) y HTML (`<!-- -->`)
- [ ] **FM-01**: Frontmatter YAML: traducir campos en lista blanca (`title`, `description`, `summary`)
- [ ] **FM-02**: Claves técnicas YAML (`slug`, `date`, `layout`, `id`) nunca se traducen

### Batch UX & Cost (Phase C)

- [ ] **JOB-01**: Traducción por lote usa jobs con ID y progreso real vía SSE
- [ ] **JOB-02**: UI muestra archivo actual, segmentos y porcentaje durante lote
- [ ] **JOB-03**: El usuario puede cancelar un job en curso
- [ ] **JOB-04**: Lote devuelve ZIP parcial + `errors.json` si algunos archivos fallan
- [ ] **COST-01**: Endpoint `POST /api/translate/estimate` devuelve segmentos, chars y coste estimado
- [ ] **COST-02**: UI muestra estimación antes de confirmar traducción grande

### Team Scale (Phase D)

- [ ] **MULTI-01**: Usuario puede seleccionar varios idiomas destino en una pasada
- [ ] **MULTI-02**: Salida multi-idioma en ZIP con nombres `stem.{lang}.md`
- [ ] **DOCKER-01**: `Dockerfile` multi-stage con `uv.lock` y runtime non-root
- [ ] **DOCKER-02**: `docker-compose.yml` con volúmenes para `data/` y `output/`
- [ ] **SEC-01**: Variables de entorno para CORS allowlist y bind address documentadas
- [ ] **SEC-02**: Límite de tamaño de upload y TTL/limpieza de `output/` configurable

### Editorial & Pro (Phase E)

- [ ] **REV-01**: Modo revisión permite editar segmentos traducidos antes de exportar
- [ ] **REV-02**: Segmentos marcados como «dudosos» destacados para revisión
- [ ] **FALL-01**: Fallback automático DeepL → OpenAI cuando DeepL falla por cuota/idioma
- [ ] **DIFF-01**: Vista diff lado a lado original vs traducción (texto traducible resaltado)
- [ ] **WATCH-01**: CLI `md-translate watch` monitoriza carpeta y escribe traducciones en salida
- [ ] **TREE-01**: CLI traduce árbol de docs respetando `.gitignore` del proyecto fuente
- [ ] **TONE-01**: Selector formal/informal para DeepL y tono LLM
- [ ] **HIST-01**: Historial de traducciones recientes opt-in (sin API keys ni contenido sensible por defecto)
- [ ] **EXPORT-01**: Export opcional a HTML autocontenido desde Markdown traducido

## v2 Requirements (deferred)

- [ ] **V2-01**: Export PDF (WeasyPrint/Pandoc)
- [ ] **V2-02**: Plugin Obsidian o VS Code
- [ ] **V2-03**: Multi-tenant con API key por usuario
- [ ] **V2-04**: Redis job store para despliegue multi-worker

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Traducción directa PDF/DOCX | Pipeline distinto; usar MD intermedio |
| MT offline sin LLM como calidad principal | Inferior en modismos |
| Reescritura libre del documento | Fuera del core value |
| SaaS público sin auth en v1 | Riesgo seguridad; Phase D solo con hardening |

## Traceability

| Requirement | Phase | Status |
| ----------- | ----- | ------ |
| HARD-01 | 0 | Complete |
| HARD-02 | 0 | Complete |
| HARD-03 | 0 | Complete |
| HARD-04 | 0 | Complete |
| PIPE-01 | 1 | Pending |
| GLOS-01 | 1 | Pending |
| GLOS-02 | 1 | Pending |
| GLOS-03 | 1 | Pending |
| TM-01 | 1 | Pending |
| TM-02 | 1 | Pending |
| TM-03 | 1 | Pending |
| CLI-01 | 1 | Pending |
| CLI-02 | 1 | Pending |
| CLI-03 | 1 | Pending |
| CLI-04 | 1 | Pending |
| CLI-05 | 1 | Pending |
| VAL-01 | 2 | Pending |
| VAL-02 | 2 | Pending |
| VAL-03 | 2 | Pending |
| PREV-01 | 2 | Pending |
| PREV-02 | 2 | Pending |
| PARS-01 | 2 | Pending |
| PARS-02 | 2 | Pending |
| FM-01 | 2 | Pending |
| FM-02 | 2 | Pending |
| JOB-01 | 3 | Pending |
| JOB-02 | 3 | Pending |
| JOB-03 | 3 | Pending |
| JOB-04 | 3 | Pending |
| COST-01 | 3 | Pending |
| COST-02 | 3 | Pending |
| MULTI-01 | 4 | Pending |
| MULTI-02 | 4 | Pending |
| DOCKER-01 | 4 | Pending |
| DOCKER-02 | 4 | Pending |
| SEC-01 | 4 | Pending |
| SEC-02 | 4 | Pending |
| REV-01 | 5 | Pending |
| REV-02 | 5 | Pending |
| FALL-01 | 5 | Pending |
| DIFF-01 | 5 | Pending |
| WATCH-01 | 5 | Pending |
| TREE-01 | 5 | Pending |
| TONE-01 | 5 | Pending |
| HIST-01 | 5 | Pending |
| EXPORT-01 | 5 | Pending |

---
*Requirements defined: 2026-05-28*  
*Last updated: 2026-05-28 after roadmap creation*
