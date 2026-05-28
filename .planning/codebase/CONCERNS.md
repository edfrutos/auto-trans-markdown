# Codebase Concerns

**Analysis Date:** 2026-05-28

## Tech Debt

**API sin autenticación ni cuotas por cliente:**
- Issue: Cualquier cliente que alcance el servidor puede invocar `/api/translate`, `/api/translate/file` y `/api/translate/batch`; el coste de OpenAI/DeepL corre con las claves del proceso servidor.
- Files: `src/main.py`, `static/js/app.js`
- Impact: Exposición accidental si `HOST` se cambia a `0.0.0.0` o el servicio se publica sin proxy; abuso de cuota y fuga de contenido traducido a terceros (proveedores MT).
- Fix approach: API key de servicio, reverse proxy con auth, o modo solo localhost documentado; límites por IP/sesión antes de llamar a `translate_segments`.

**CORS abierto a cualquier origen:**
- Issue: `CORSMiddleware` con `allow_origins=["*"]`, `allow_methods=["*"]`, `allow_headers=["*"]`.
- Files: `src/main.py` (aprox. líneas 38–43)
- Impact: Sitios externos pueden llamar a la API desde el navegador del usuario si el servidor es accesible en red.
- Fix approach: Lista blanca de orígenes vía variable de entorno; por defecto solo el origen del propio host en desarrollo.

**Progreso de traducción no conectado:**
- Issue: `ProgressEvent` en `src/main.py` no se usa en ningún endpoint; `translate_segments` acepta `on_progress` pero la API nunca lo pasa. La UI muestra una barra fija al 30 % sin datos reales (`static/js/app.js`).
- Files: `src/main.py`, `src/translator.py`, `static/js/app.js`
- Impact: Lotes largos son «caja negra»; deuda alineada con NOTEBOOK.md §5 (SSE / progreso en tiempo real).
- Fix approach: Endpoint SSE o WebSocket con job ID; invocar `on_progress` desde el executor o refactor async nativo.

**Acumulación de archivos en `output/`:**
- Issue: Cada traducción por archivo escribe `OUTPUT_DIR / f"{uuid}_{out_name}"` sin limpieza ni TTL.
- Files: `src/main.py` (`translate_file`, creación de `OUTPUT_DIR`)
- Impact: Crecimiento de disco; archivos pueden contener documentación privada (aunque `output/` está en `.gitignore`).
- Fix approach: Borrar tras `FileResponse`, stream en memoria, o tarea de limpieza periódica; volumen Docker según NOTEBOOK §11.

**Doble manifest de dependencias:**
- Issue: Dependencias declaradas en `pyproject.toml` y duplicadas en `requirements.txt` sin versión fijada en lockfile del repo.
- Files: `pyproject.toml`, `requirements.txt`
- Impact: Deriva de versiones entre instalaciones (`pip install -r` vs `pip install .`).
- Fix approach: Una fuente de verdad (`pyproject.toml` + `pip freeze` o `uv.lock`) y README actualizado.

**Entry point `md-translate` engañoso:**
- Issue: `[project.scripts] md-translate = "src.main:run"` arranca el servidor web, no una CLI de traducción (planeada en NOTEBOOK §3).
- Files: `pyproject.toml`, `src/main.py` (`run()`)
- Impact: Expectativa rota en CI/automatización; confusión con el nombre del paquete.
- Fix approach: Nuevo `src/cli.py` y script separado (`md-translate-server` vs `md-translate`).

**Frontmatter YAML siempre protegido:**
- Issue: Bloque `---` inicial se marca entero como `PROTECTED`; no hay traducción selectiva de `title` / `description`.
- Files: `src/parser.py` (bucle frontmatter, aprox. líneas 118–128)
- Impact: Metadatos orientados al usuario no se traducen; desalineado con NOTEBOOK §8.
- Fix approach: Parser YAML con lista blanca/negra de campos antes de segmentar.

**Comentarios de código solo en shell `#`:**
- Issue: Solo fences `bash`/`sh`/`zsh`/etc. traducen comentarios `#`; Python `//`, HTML `<!-- -->`, SQL `--` quedan protegidos.
- Files: `src/parser.py` (`SHELL_LANGS`, `_append_shell_line`)
- Impact: Documentación en otros lenguajes no se localiza en comentarios; NOTEBOOK §7 pendiente.
- Fix approach: Estrategia por etiqueta de fence y tests por lenguaje.

**Validación post-traducción ausente:**
- Issue: No existe `src/validator.py` ni comprobación de fences/enlaces tras traducir.
- Files: `src/main.py`, `src/parser.py` (solo segmentación previa)
- Impact: Errores estructurales o alucinaciones del LLM pasan desapercibidos; NOTEBOOK §6.
- Fix approach: Módulo validator con informe JSON en respuesta API y opcionalmente en ZIP de lote.

**Funcionalidades de producto planificadas sin implementar:**
- Issue: NOTEBOOK.md documenta glosario, memoria de traducción, CLI, preview Markdown, estimación de coste, fallback de proveedor, Docker, etc., sin código correspondiente.
- Files: `NOTEBOOK.md` (referencia); ausencia de `src/glossary.py`, `src/memory.py`, `src/cli.py`, `src/validator.py`
- Impact: Coherencia terminológica, coste API y UX de lote limitados hasta implementar fases A–E del notebook.
- Fix approach: Seguir orden recomendado en NOTEBOOK (fase A: glosario + memoria + CLI).

## Known Bugs

**Decodificación con fallback `latin-1` y `errors="replace"`:**
- Symptoms: Archivos UTF-8 mal formados se «traducen» con caracteres sustitutos sin error claro al usuario.
- Files: `src/main.py` (`_decode_upload`)
- Trigger: Subir `.md` con bytes inválidos en UTF-8.
- Workaround: Validar UTF-8 estricto y devolver HTTP 400 con mensaje explícito.

**Lote aborta por completo ante el primer fallo:**
- Symptoms: Si un archivo del lote falla en la API de traducción, no se entrega ZIP parcial; el cliente pierde el trabajo de archivos ya procesados en memoria.
- Files: `src/main.py` (`translate_batch`, bucle con `raise HTTPException` en excepción)
- Trigger: Un archivo grande o idioma no soportado por DeepL en medio de un lote de 20.
- Workaround: Traducir archivos de uno en uno desde la UI modo archivo.

**`source_lang` sin validación en rutas multipart:**
- Symptoms: Solo `POST /api/translate` valida `target_lang` contra `LANGUAGE_NAMES`; `/api/translate/file` y `/api/translate/batch` aceptan cualquier `source_lang` en Form.
- Files: `src/main.py` (`translate_file`, `translate_batch` vs `translate_text`)
- Trigger: `source_lang=xx` inválido → error 502/503 del proveedor o prompt confuso en OpenAI.
- Workaround: Usar códigos de la lista `/api/languages`.

**Detección HTML `<pre>` / `<code>` frágil:**
- Symptoms: Líneas con `<code` abren modo protegido hasta `</pre>` o `</code>`; mezclas anidadas o `<code>` sin cierre pueden proteger o exponer bloques incorrectamente.
- Files: `src/parser.py` (bucle `in_html_pre`, aprox. líneas 133–148)
- Trigger: Markdown con HTML embebido no estándar.
- Workaround: Usar fences ``` en lugar de HTML crudo.

**Segmentos sin traducción conservan texto original sin aviso:**
- Symptoms: Si el mapa `translations` no incluye un índice, `reassemble` deja el segmento original (`src/parser.py` rama `else` en `reassemble`).
- Files: `src/parser.py` (`reassemble`)
- Trigger: Desajuste parcial entre segmentos enviados y respuesta del modelo (mitigado por validación de conteo en `_parse_openai_response`, pero no en todos los caminos DeepL).
- Workaround: Comparar `segments_translated` con longitud de `translatable` y fallar si difieren.

## Security Considerations

**Secretos solo en entorno — nunca en git:**
- Risk: Commit accidental de `.env` con `OPENAI_API_KEY` / `DEEPL_API_KEY`.
- Files: `.env` (presente localmente, no leer en docs), `.env.example`, `.gitignore`, `.git/hooks/pre-commit` (`git secrets`)
- Current mitigation: `.gitignore` ignora `.env`, `.env.*` salvo `!.env.example`; hook `git secrets --pre_commit_hook`.
- Recommendations: Mantener regla explícita en README y CI; ampliar `.env.example` con placeholders DeepL (`DEEPL_API_KEY`, `DEEPL_API_URL`, `TRANSLATION_PROVIDER`) sin valores reales.

**Filtración de detalles internos en respuestas HTTP 502:**
- Risk: `raise HTTPException(502, f"Error de traducción: {e}")` expone mensajes de excepción del SDK (URLs, códigos, fragmentos de respuesta).
- Files: `src/main.py` (handlers de `translate_text`, `translate_file`, `translate_batch`)
- Current mitigation: `logger.exception` en servidor.
- Recommendations: Mensaje genérico al cliente; correlación por `request_id` en logs.

**Sin límite de tamaño de subida:**
- Risk: `await file.read()` carga el archivo completo en RAM; lotes de 20 archivos grandes pueden agotar memoria.
- Files: `src/main.py`
- Current mitigation: Máximo 20 archivos por lote.
- Recommendations: `MAX_UPLOAD_BYTES` por archivo y total del lote; streaming rechazado si supera umbral.

**Contenido sensible enviado a terceros:**
- Risk: Todo segmento traducible se envía a OpenAI o DeepL; no hay redacción ni opt-out.
- Files: `src/translator.py`, `src/main.py`
- Current mitigation: Uso local asumido en README (`127.0.0.1`).
- Recommendations: Aviso en UI; modo «solo local» si se integra Ollama vía `OPENAI_BASE_URL`.

**`innerHTML` con nombres de archivo en listado de lote:**
- Risk: XSS si un nombre de archivo contiene HTML (arrastre desde ZIP malicioso).
- Files: `static/js/app.js` (`els.batchList.innerHTML`)
- Current mitigation: Uso típico con nombres `.md` controlados por el usuario.
- Recommendations: `textContent` / `createElement` o escape explícito.

**Servidor de desarrollo en producción:**
- Risk: `uvicorn.run(..., reload=True)` en `run()` no es adecuado para despliegue.
- Files: `src/main.py` (`run`)
- Recommendations: `reload` solo con flag de entorno; Docker con worker fijo (NOTEBOOK §11).

## Performance Bottlenecks

**Traducción síncrona bloqueando el pool de threads:**
- Problem: `loop.run_in_executor(None, partial(translate_segments, ...))` ejecuta lotes con `time.sleep` en reintentos dentro del hilo del executor por defecto.
- Files: `src/main.py`, `src/translator.py` (`_translate_openai_batch`, `_translate_deepl_batch`)
- Cause: I/O de red y backoff síncronos en thread pool compartido.
- Improvement path: Cliente async de OpenAI, semáforo de concurrencia, o cola de trabajos (Celery/RQ) para lotes.

**Lote secuencial archivo a archivo:**
- Problem: `translate_batch` procesa uploads en un `for` sin paralelismo entre archivos.
- Files: `src/main.py` (`translate_batch`)
- Cause: Diseño simple; un fallo detiene todo el ZIP.
- Improvement path: `asyncio.gather` con límite de concurrencia y ZIP incremental o job asíncrono.

**Sin memoria de traducción ni caché:**
- Problem: Mismos segmentos en varios archivos o re-traducciones disparan llamadas API repetidas.
- Files: `src/translator.py`
- Cause: No implementado (NOTEBOOK §2).
- Improvement path: SQLite/JSON con clave hash antes de `_translate_*_batch`.

**Barra de progreso del cliente no refleja trabajo real:**
- Problem: UI fija 30 % durante toda la petición HTTP.
- Files: `static/js/app.js` (`setLoading`)
- Improvement path: Consumir eventos de progreso reales del backend.

## Fragile Areas

**Parser `segment_markdown`:**
- Files: `src/parser.py` (~231 líneas)
- Why fragile: Muchas ramas (frontmatter, fences, indentación, HTML, inline code, shell comments); un cambio en una rama afecta índices de `Segment.index` y `reassemble`.
- Safe modification: Añadir test en `tests/test_parser.py` por cada caso nuevo antes de tocar lógica; verificar unicidad de índices (`test_no_duplicate_blank_lines` como plantilla).
- Test coverage: Solo parser; sin tests de regresión para HTML o frontmatter mal cerrado.

**Parser de respuesta OpenAI JSON:**
- Files: `src/translator.py` (`_parse_openai_response`, división recursiva de lotes)
- Why fragile: Depende de que el modelo devuelva JSON válido; strip de fences markdown en respuesta.
- Safe modification: Mantener `response_format={"type": "json_object"}`; ampliar tests con respuestas grabadas (fixtures).
- Test coverage: Ninguno en `tests/`.

**Mapa de idiomas DeepL vs lista UI:**
- Files: `src/translator.py` (`DEEPL_TARGET_MAP`, `LANGUAGE_NAMES`), `src/main.py` (`list_languages`)
- Why fragile: La UI ofrece catalán, gallego, euskera, etc.; DeepL falla en runtime con `ValueError` no validado en API antes de traducir.
- Safe modification: Filtrar idiomas en `/api/languages` según `get_provider()` o validar `target_lang` en todas las rutas.

## Scaling Limits

**Proceso único FastAPI + uvicorn:**
- Current capacity: Una instancia; traducciones compiten por el mismo pool de threads y las mismas API keys.
- Limit: Picos de lote o documentos muy segmentados encolan peticiones; rate limits 429 de proveedores.
- Scaling path: Cola de jobs, workers horizontales, Redis para progreso (NOTEBOOK §5), límites por tenant (NOTEBOOK §20).

**Tope duro de 20 archivos por lote:**
- Files: `src/main.py` (`len(files) > 20`)
- Limit: Sin configuración por entorno; clientes deben trocear manualmente.

**Constantes de lote fijas en código:**
- Files: `src/translator.py` (`BATCH_SIZE=15`, `DEEPL_BATCH_SIZE=40`, `MAX_BATCH_CHARS=4000`)
- Limit: Documentos con segmentos muy largos generan muchos viajes API; sin estimación previa (NOTEBOOK §10).

## Dependencies at Risk

**Tailwind CSS desde CDN:**
- Risk: `static/index.html` carga `https://cdn.tailwindcss.com`; sin build local la UI depende de red y del CDN.
- Impact: UI rota offline o si el CDN falla; posible cambio de comportamiento del runtime Tailwind CDN.
- Migration plan: Build Tailwind en `static/` o pin de versión compilada.

**OpenAI SDK + modelo por defecto `gpt-4o-mini`:**
- Risk: Cambios de API, precios o deprecación de modelos; `OPENAI_BASE_URL` permite proxies pero sin tests de integración.
- Files: `src/translator.py`, `.env.example`
- Impact: Fallos en despliegues con Ollama/Azure si el endpoint no soporta `response_format` JSON.
- Migration plan: Tests de contrato con mock; documentar modelos compatibles.

**Paquete `deepl` opcional en runtime:**
- Risk: Import solo en `create_deepl_client`; error en runtime si falta instalación pese a estar en dependencias del proyecto.
- Files: `src/translator.py`, `pyproject.toml`

## Missing Critical Features

**Glosario de términos fijos (NOTEBOOK §1, prioridad alta):**
- Problem: No hay `glossary.json` ni inyección en prompt; términos de producto y tecnicismos se traducen libremente.
- Blocks: Coherencia en documentación técnica y lotes grandes.

**Memoria de traducción (NOTEBOOK §2, prioridad alta):**
- Problem: Sin persistencia de segmentos traducidos.
- Blocks: Coste API, velocidad y consistencia frase a frase en lotes.

**CLI real (NOTEBOOK §3):**
- Problem: No hay `src/cli.py`; el script `md-translate` no traduce archivos en terminal.
- Blocks: Pipelines CI/CD sin navegador.

**Fallback automático DeepL → OpenAI (NOTEBOOK §13):**
- Problem: Un solo `TRANSLATION_PROVIDER`; fallos no reintentan con otro proveedor.
- Blocks: Resiliencia ante cuota o idioma no soportado.

## Test Coverage Gaps

**Capa de traducción (`src/translator.py`):**
- What's not tested: Lotes OpenAI/DeepL, reintentos, `_parse_openai_response`, `_chunk_items`, errores de proveedor.
- Files: `src/translator.py`; ausencia de `tests/test_translator.py`
- Risk: Regresiones en JSON del modelo o en división de lotes pasan a producción.
- Priority: High

**API FastAPI (`src/main.py`):**
- What's not tested: Endpoints HTTP, validación de idiomas, batch ZIP, `_decode_upload`, manejo de errores 502/503.
- Files: `src/main.py`; sin `tests/test_main.py` ni `httpx`/`TestClient`
- Risk: Cambios en contratos API rompen la UI sin aviso.
- Priority: High

**Cliente web (`static/js/app.js`):**
- What's not tested: Flujos editor/archivo/lote, manejo de errores API.
- Risk: Roturas de UX en refactors de API.
- Priority: Medium

**Cobertura existente limitada al parser:**
- Files: `tests/test_parser.py` (6 tests)
- Risk: El núcleo de valor (traducción + API) carece de red de seguridad automatizada.
- Priority: High

---

*Concerns audit: 2026-05-28. Roadmap planificado: `NOTEBOOK.md`. Secretos: solo variables de entorno (`.env` ignorado por git; no commitear claves).*
