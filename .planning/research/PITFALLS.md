# Domain Pitfalls — Markdown Translation & Localization

**Domain:** Herramientas de traducción/localización de Markdown técnico (preservación de sintaxis, lotes, proveedores MT/LLM)  
**Project:** MarkDown Auto Translator (brownfield)  
**Researched:** 2026-05-28  
**Overall confidence:** HIGH (codebase audit + patrones de industria verificados en fuentes oficiales/comunidad 2025–2026)

---

## Critical Pitfalls

Errores que provocan documentos rotos, pérdida de confianza del lector o reescrituras arquitectónicas.

### Pitfall 1: Tratar el `.md` como texto plano

**What goes wrong:** Se envía el archivo completo a Google Translate, CAT genérico o LLM sin segmentación; se traducen fences, claves YAML, URLs, nombres de variables y comandos CLI. El resultado no renderiza o las instrucciones fallan al ejecutarlas.

**Why it happens:** Markdown *parece* texto; los equipos subestiman nodos estructurales (frontmatter, `[texto](url)`, `` `inline` ``, bloques indentados).

**Consequences:** Frontmatter inválido (claves traducidas), snippets de código inutilizables, 404 en enlaces internos/externos, pérdida de SEO en `title`/`description`.

**Prevention:**
- Pipeline obligatorio: **parse → traducir solo segmentos TRANSLATABLE → reassemble por índice** (ya en `src/parser.py`; no añadir atajos que salten este paso).
- Documentar en README/UI la lista de «zonas prohibidas» (código, URLs, paths, badges).
- Tests de regresión: mismo conteo de fences, enlaces y backticks antes/después.

**Detection:** Renderizar MD traducido; diff estructural origen vs salida; validador post-traducción (NOTEBOOK §6).

**Phase mapping:** Transversal — **refuerzo en Fase B** (validación + preview). No degradar el parser en fases C–E.

**Codebase status:** Mitigado en MVP para fences, inline code, frontmatter bloqueado; **sin validación automática** tras traducir (`CONCERNS.md`).

**Sources:** [MetalGlot — Markdown localization](https://metalglot.com/blog/markdown/) (MEDIUM), [Lara Translate — MD syntax](https://blog.laratranslate.com/translate-a-markdown-file-online/) (MEDIUM), alineado con `PROJECT.md` Core Value.

---

### Pitfall 2: Desincronización de chunks y placeholders (fences / listas)

**What goes wrong:** Al dividir por líneas o por tokens sin agrupar contexto, un bloque de código o un ítem de lista queda partido entre dos llamadas API; los placeholders (`@@BLOCK@@`) no se restauran y reaparecen fences sin cerrar o listas rotas.

**Why it happens:** Chunking greedy por caracteres (`MAX_BATCH_CHARS=4000`) sin unidad atómica de bloque MD; HTML `<pre>`/`<code>` con heurística frágil en `parser.py`.

**Consequences:** Contenido omitido, fences huérfanos, bullets desalineados con su código de ejemplo (patrón documentado en pipelines de traducción a escala).

**Prevention:**
- Tratar cada fence + info string como **unidad atómica** en segmentación y en chunking del traductor (no partir un `Segment` entre lotes).
- Agrupar ítems de lista con líneas de continuación e indentación antes de trocear (`CONCERNS.md` — área frágil `segment_markdown`).
- Añadir tests para: fence sin cierre, fence de longitud variable (` ``` ` vs ` ```` `), listas con bloque indentado.

**Detection:** Conteo de ` ``` ` / `~~~` par; parser AST o markdown-it en validador; informe por archivo en lote.

**Phase mapping:** **Fase B** (validator); **investigación previa a Fase C** si se paraleliza lote (más superficie de chunking).

**Codebase status:** Riesgo activo — parser line-based; bisect-on-failure en `translator.py` puede enmascarar desajustes parciales.

**Sources:** [Azure Feeds — Hardening MD translation pipeline](https://azurefeeds.com/2026/04/30/fixing-broken-markdown-in-ai-translation-hardening-a-production-pipeline/) (MEDIUM), `CONCERNS.md` Known Bugs (HTML pre/code).

---

### Pitfall 3: Segmentos no traducidos sin fallar (silencio en `reassemble`)

**What goes wrong:** Si el mapa `translations` no incluye un índice, `reassemble` conserva el texto original sin aviso; el usuario cree que todo el documento está en el idioma destino.

**Why it happens:** Diseño tolerante en `parser.py` (`else` en `reassemble`); validación de conteo solo en ruta OpenAI (`_parse_openai_response`), no garantizada en todos los caminos DeepL.

**Consequences:** Mezcla bilingüe invisible; publicación de docs «traducidas» con párrafos en idioma fuente; incumplimiento de Core Value.

**Prevention:**
- Tras cada traducción: `len(translations) == len(collect_translatable)` o HTTP 502 con segmentos faltantes.
- Incluir en respuesta API lista de índices omitidos (modo debug) y flag `complete: false`.
- Tests de contrato en `tests/test_translator.py` con respuestas JSON incompletas.

**Detection:** Comparar `segments_translated` vs translatable; diff idioma heurístico en segmentos largos.

**Phase mapping:** **Pre-Fase A / transversal** (calidad mínima); **Fase B** lo eleva a error bloqueante opcional.

**Codebase status:** Bug conocido — `CONCERNS.md` Known Bugs.

---

### Pitfall 4: Frontmatter «todo o nada»

**What goes wrong:** Bloque `---` entero protegido → `title`/`description` no localizados; o, en el extremo opuesto, traducir claves YAML (`title` → `título`) y romper SSG (Hugo, Jekyll, Docusaurus).

**Why it happens:** Parser actual marca frontmatter completo como PROTECTED (`parser.py` ~118–128); sin parser YAML selectivo.

**Consequences:** Metadatos SEO en idioma incorrecto; builds que ignoran campos; doble trabajo manual en cada artículo.

**Prevention:**
- Lista blanca/negra de campos (`NOTEBOOK §8`); PyYAML con tipos preservados; fallback: bloque entero protegido si YAML inválido.
- Nunca traducir nombres de clave ni URLs en frontmatter.

**Detection:** Diff de claves YAML; schema del generador de sitio.

**Phase mapping:** **Fase B** (junto a validación) o sub-fase explícita antes de multi-destino **Fase D**.

**Codebase status:** Deuda documentada — `CONCERNS.md`, `NOTEBOOK.md` §8.

---

### Pitfall 5: Enlaces internos y anclas rotas tras traducir encabezados

**What goes wrong:** `[ver sección](#instalacion)` sigue apuntando al slug en español mientras el H2 traducido genera `#installation` en el renderizador; enlaces relativos `./other.md` traducidos o fragmentos alterados por el LLM.

**Why it happens:** Solo se traduce el texto visible del enlace, no se reconcilia el árbol de headings post-hoc; URLs no están en zona PROTECTED explícita si el segmento es línea completa mezclada.

**Consequences:** 404 locales, TOC roto, CI de docs que falla en link checkers.

**Prevention:**
- Proteger URL/path en `[texto](url)` e `![alt](path)` (solo traducir texto/alt).
- Post-paso: parsear headings traducidos, regenerar slugs estilo GitHub, reescribir fragmentos internos (patrón Co-op Translator / GenAIScript).
- Validador: conjunto de URLs externas idéntico origen vs salida.

**Detection:** `markdown-it` + comparación de sets de URIs; readme-i18n-sentinel-style checks en CI.

**Phase mapping:** **Fase B** (validator ampliado); crítico antes de **Fase D** (multi-destino y árbol Git §16).

**Codebase status:** No implementado; riesgo MEDIO en líneas con enlaces embebidos en segmentos TRANSLATABLE.

**Sources:** [GenAIScript — continuous translations](https://microsoft.github.io/genaiscript/blog/continuous-translations/) (HIGH — validación explícita de URLs), [readme-i18n-sentinel](https://github.com/sugurutakahashi-1234/readme-i18n-sentinel) (MEDIUM).

---

### Pitfall 6: Lotes LLM con JSON y conteo de segmentos inestable

**What goes wrong:** El modelo devuelve menos/más entradas, anida arrays, envuelve JSON en fences markdown, o «divide» una traducción en varias cadenas; el pipeline acepta parcialmente o reintenta con bisect sin alertar al usuario.

**Why it happens:** `response_format json_object` reduce pero no elimina fallos; prompts con arrays planos son más frágiles que tool-use con propiedades fijas por índice.

**Consequences:** Retraducciones costosas, texto mixto, confianza cero en lotes de 15+ segmentos.

**Prevention:**
- Validación estricta de cardinalidad antes de `reassemble`.
- Considerar function calling / propiedades nombradas `t0…tN` para lotes OpenAI (HIGH confidence en mejoría de fiabilidad).
- Reducir `BATCH_SIZE` cuando aumente tasa de fallo; fixtures de respuestas malformadas en tests.

**Detection:** Métrica `batch_parse_failures`; logs de bisect recursivo.

**Phase mapping:** **Pre-Fase A** (tests translator); **Fase A** no sustituye esta capa — glosario aumenta tamaño de prompt y presión sobre JSON.

**Codebase status:** Mitigación parcial (`_parse_openai_response`, chunk split); sin tests — `CONCERNS.md` Test Coverage Gaps HIGH.

**Sources:** [DEV — LLM structured output in translator](https://dev.to/cloudyview/how-i-fixed-llm-structured-output-failures-in-a-powerpoint-translator-0-errors-on-1214-20g) (MEDIUM).

---

### Pitfall 7: Coherencia terminológica sin glosario ni memoria de traducción

**What goes wrong:** «API Gateway», «dashboard» y la misma frase en 20 archivos se traducen de formas distintas; coste API multiplicado por segmentos repetidos.

**Why it happens:** Cada segmento es independiente; DeepL/OpenAI sin reglas de producto; prioridad de negocio pospuesta.

**Consequences:** Revisiones manuales masivas en docs técnicas; incumplimiento del Core Value de «coherencia terminológica».

**Prevention:**
- **Fase A:** `glossary.json` + inyección en prompt (OpenAI) y placeholders (DeepL); TM SQLite con hash `text+source+target`.
- Validar glosario case-sensitive y por par de idiomas (Azure Translator glossary guidance).
- Métricas: cache hit %, términos glosario violados (heurística post-hoc).

**Detection:** Diff entre archivos del mismo lote; auditoría de términos prohibidos.

**Phase mapping:** **Fase A** (entregable principal NOTEBOOK).

**Codebase status:** Ausente — `CONCERNS.md` Missing Critical Features §1–2.

**Sources:** [Azure AI Docs — glossaries](https://github.com/MicrosoftDocs/azure-ai-docs/blob/main/articles/ai-services/translator/document-translation/how-to-guides/create-use-glossaries.md) (HIGH).

---

### Pitfall 8: Exponer API de traducción sin auth ni límites

**What goes wrong:** `HOST=0.0.0.0`, CORS `*`, sin cuotas → terceros consumen cuota OpenAI/DeepL y filtran contenido sensible a proveedores MT.

**Why it happens:** Diseño «local first» que escala a red interna sin hardening.

**Consequences:** Coste impredecible, fuga de IP/docs, violación de políticas de datos.

**Prevention:**
- Por defecto `127.0.0.1`; API key de servicio o proxy con auth antes de **Fase D** (Docker).
- Límites `MAX_UPLOAD_BYTES`, rate limit por IP; mensajes 502 genéricos (no filtrar SDK).
- Aviso explícito en UI: contenido sale a terceros.

**Detection:** Escaneo de despliegue; pruebas de carga no autorizada.

**Phase mapping:** **Pre-Fase D** (obligatorio antes de Docker/equipo); **Fase E** si multi-tenant §20.

**Codebase status:** Deuda crítica — `CONCERNS.md` Security, Tech Debt.

---

### Pitfall 9: Lote «todo o nada» ante el primer fallo

**What goes wrong:** Un archivo inválido en un ZIP de 20 hace fallar toda la petición; trabajo ya traducido en memoria se pierde para el cliente.

**Why it happens:** `translate_batch` hace `raise HTTPException` en primera excepción.

**Consequences:** UX catastrófica en carpetas heterogéneas; equipos evitan el modo lote.

**Prevention:**
- ZIP parcial + manifest `errors.json`; o job async con SSE (**Fase C**) y estado por archivo.
- Validar `source_lang`/`target_lang` en todas las rutas multipart (igual que `/api/translate`).

**Detection:** Test de lote con un archivo «veneno»; métrica `batch_partial_success`.

**Phase mapping:** **Fase C** (progreso + resiliencia); mitigación mínima posible antes en handler batch.

**Codebase status:** Bug conocido — `CONCERNS.md` Known Bugs.

---

### Pitfall 10: UI de idiomas incompatible con el proveedor activo

**What goes wrong:** Usuario elige catalán/gallego/euskera en UI; DeepL lanza `ValueError` en runtime; OpenAI podría traducir pero la lista no está filtrada.

**Why it happens:** `LANGUAGE_NAMES` unificado; `DEEPL_TARGET_MAP` más restrictivo; validación solo en `POST /api/translate`.

**Consequences:** 502 confuso; pérdida de confianza en selector de idioma.

**Prevention:**
- `/api/languages?provider=deepl` o filtrado según `get_provider()`; validar `target_lang` en file/batch.
- Documentar matriz idioma × proveedor en README.

**Phase mapping:** **Pre-Fase A** (contrato API); **Fase A** CLI debe compartir misma validación.

**Codebase status:** Fragile area — `CONCERNS.md`.

---

## Moderate Pitfalls

### Pitfall 11: Traducir comentarios de código sin reglas por lenguaje

**What goes wrong:** Traducir `#` dentro de strings Python, o `//` en URLs; o dejar comentarios útiles sin traducir en `python`/`js` porque solo `bash` está soportado.

**Prevention:** Detección por etiqueta de fence; tests por lenguaje; no traducir shebangs, pragmas, URLs (`NOTEBOOK §7`).

**Phase mapping:** **Fase B** o extensión parser post-A.

**Codebase status:** Solo shell — `CONCERNS.md`.

---

### Pitfall 12: Decodificación permisiva (UTF-8 → latin-1)

**What goes wrong:** Bytes inválidos se convierten en `` con `errors="replace"`; traducción «exitosa» de texto corrupto.

**Prevention:** UTF-8 estricto + HTTP 400 con mensaje claro.

**Phase mapping:** Transversal (fix pequeño en `main.py`).

**Codebase status:** Known Bug — `CONCERNS.md`.

---

### Pitfall 13: Progreso de UI falso

**What goes wrong:** Barra al 30 % fija durante toda la petición; lotes largos percibidos como colgados; usuarios reenvían y duplican coste.

**Prevention:** Conectar `ProgressEvent` / `on_progress` vía SSE (**Fase C**); cancelación de job.

**Phase mapping:** **Fase C**.

**Codebase status:** Tech debt — `CONCERNS.md`, `NOTEBOOK §5`.

---

### Pitfall 14: Coste y tokens impredecibles en lotes grandes

**What goes wrong:** Sin estimación previa, equipos disparan 20 archivos × miles de segmentos; rate limit 429 y factura sorpresa.

**Prevention:** Endpoint `estimate` post-segmentación (**Fase C**); TM en **Fase A**; umbrales configurables.

**Phase mapping:** **Fase A** (TM), **Fase C** (estimate UI).

**Codebase status:** NOTEBOOK §10 sin implementar.

---

### Pitfall 15: Un solo proveedor sin fallback

**What goes wrong:** Cuota DeepL agotada o idioma no soportado detiene el pipeline; no hay `TRANSLATION_FALLBACK=openai`.

**Prevention:** Cadena configurada de proveedores con registro de qué segmento usó qué motor (**Fase A/C** según prioridad).

**Phase mapping:** Puede entrar en **Fase A** (resiliencia) o **Fase C** (operaciones).

**Codebase status:** NOTEBOOK §13 — ausente.

---

### Pitfall 16: Acumulación en `output/` y RAM en uploads

**What goes wrong:** Disco lleno con MD privados; `await file.read()` sin tope agota memoria en lotes.

**Prevention:** TTL/stream/borrado post-`FileResponse`; `MAX_UPLOAD_BYTES` total y por archivo.

**Phase mapping:** **Fase D** (volúmenes Docker); límites antes de despliegue.

**Codebase status:** `CONCERNS.md` Performance / Security.

---

### Pitfall 17: `innerHTML` con nombres de archivo en lote

**What goes wrong:** XSS si nombre de archivo contiene HTML malicioso.

**Prevention:** `textContent` / `createElement` en `static/js/app.js`.

**Phase mapping:** Transversal (fix UI pequeño).

**Codebase status:** Security consideration — `CONCERNS.md`.

---

## Minor Pitfalls

### Pitfall 18: Entry point `md-translate` arranca servidor, no CLI

**What goes wrong:** Pipelines CI esperan traducción en terminal; reciben uvicorn.

**Prevention:** `md-translate` → `src/cli.py`; script separado para servidor (**Fase A**).

**Phase mapping:** **Fase A**.

---

### Pitfall 19: Doble manifest de dependencias sin lockfile

**What goes wrong:** `requirements.txt` y `pyproject.toml` divergen entre máquinas.

**Prevention:** Una fuente de verdad + lock; actualizar README.

**Phase mapping:** **Fase D** (Docker) o housekeeping pre-D.

---

### Pitfall 20: Tailwind desde CDN en UI offline

**What goes wrong:** UI rota sin red o si CDN cambia comportamiento.

**Prevention:** Build estático pinneado en **Fase D** o antes si se empaqueta Docker.

**Phase mapping:** **Fase D**.

---

### Pitfall 21: Preview Markdown sin sanitizar

**What goes wrong:** Si **Fase B** renderiza MD con `marked.js` sin DOMPurify, XSS en preview de contenido no confiable.

**Prevention:** Sanitizar HTML; no ejecutar scripts del documento traducido.

**Phase mapping:** **Fase B** (NOTEBOOK §4 criterios).

---

## Phase-Specific Warnings

| Phase (NOTEBOOK) | Entregables | Pitfalls más probables si se implementan mal | Mitigación prioritaria |
|------------------|-------------|-----------------------------------------------|-------------------------|
| **Pre-A** (hardening MVP) | Tests translator/API, validación conteo segmentos, idiomas por proveedor, UTF-8 estricto | #3, #6, #10, #12 | `tests/test_translator.py`, `tests/test_main.py`; fallar si traducciones incompletas |
| **A** | Glosario + TM + CLI | #7, #6 (prompt más largo), #18, glosario case-insensitive | TM antes de llamada API; glosario por par `en→es`; CLI comparte parser+validator |
| **B** | Validator + preview render | #1, #2, #5, #21, falso positivo en ratio longitud | Checks fences/enlaces/headings; reconciliación anclas; sanitizar preview |
| **C** | SSE progreso + estimate | #13, #9, #14, chunking agresivo en paralelo | Job ID; ZIP parcial; no paralelizar sin unidades atómicas (#2) |
| **D** | Multi-destino + Docker | #5, #8, #16, #14 (rate limits × N idiomas) | Auth antes de imagen pública; límites upload; TM compartida entre idiomas del mismo origen |
| **E** | Revisión + watch + diff | #3 (editar segmentos manualmente), drift estructural en watch | Versionar segmentos; validator en cada guardado watch |

### Orden de roadmap vs riesgo

El orden A→B→C→D→E del `NOTEBOOK.md` es correcto para ROI, **pero** publicar Docker (**D**) sin cerrar #8 y #16 es un anti-patrón habitual en proyectos MD i18n «que funcionan en local». La investigación recomienda **hardening Pre-A + B antes de exponer red**.

---

## Anti-Patterns del dominio (explícitamente evitar)

| Anti-pattern | Por qué falla en MD i18n | En lugar de |
|--------------|---------------------------|-------------|
| Copiar/pegar en traductor web | Rompe estructura | API/CLI con parser |
| Traducir README único sobrescribiendo | Pierde idioma fuente y SEO | `README.es.md` + selector (convención GitHub) |
| Confiar solo en prompt «no traduzcas código» | LLM viola instrucciones | Segmentación determinista + validación |
| Lotes enormes sin TM | Coste y inconsistencia | Fase A TM |
| Desplegar sin auth «porque es interno» | Abuso y fuga | Proxy + API key |
| Validar solo «a ojo» en preview | No escala | `validator.py` + CI (readme-i18n-sentinel pattern) |

---

## What MD / localization projects get wrong (síntesis)

1. **Confunden contenido con contenedor** — traducen sintaxis Markdown como si fuera prosa.  
2. **Optimizan el LLM antes que el parser** — el 80 % de los rotos son estructurales, no semánticos.  
3. **No validan después** — asumen que «casi igual» renderiza bien.  
4. **Ignoran glosario/TM** en docs técnicas repetitivas.  
5. **Mezclan producto local y servicio multiusuario** sin auth ni límites.  
6. **Lotes opacos** — sin progreso, sin parcial, sin estimación de coste.  
7. **Frontmatter y anclas** como detalle «fase 2» que nunca llega.  
8. **Lista de idiomas marketing** ≠ capacidades del proveedor MT.  
9. **Tests solo en parser** — el valor está en translate + API (este repo).  
10. **Scripts y nombres de CLI** que no coinciden con automatización real.

Este codebase ya evita (1) en gran medida vía `parser.py`; los huecos más peligrosos hoy son (3), (4), (7), (8), (9) según `CONCERNS.md` y `PROJECT.md` Active requirements.

---

## Sources

| Source | Topic | Confidence |
|--------|-------|------------|
| `.planning/codebase/CONCERNS.md` | Deuda, bugs, seguridad, tests | HIGH (repo) |
| `NOTEBOOK.md` | Roadmap fases A–E, criterios | HIGH (repo) |
| `.planning/PROJECT.md` | Core value, alcance | HIGH (repo) |
| `.planning/codebase/ARCHITECTURE.md` | Pipeline, límites | HIGH (repo) |
| https://metalglot.com/blog/markdown/ | Plain-text trap, frontmatter, no-fly zones | MEDIUM |
| https://blog.laratranslate.com/translate-a-markdown-file-online/ | Fences, links, frontmatter keys | MEDIUM |
| https://azurefeeds.com/2026/04/30/fixing-broken-markdown-in-ai-translation-hardening-a-production-pipeline/ | Chunking, listas, fences atómicos, anclas | MEDIUM |
| https://microsoft.github.io/genaiscript/blog/continuous-translations/ | Validación URLs, nodos, QA | HIGH |
| https://github.com/sugurutakahashi-1234/readme-i18n-sentinel | CI estructura README i18n | MEDIUM |
| https://dev.to/german_yamil_e021eef8710d/how-i-translated-a-technical-ebook-from-spanish-to-english-with-semantic-qa-in-python-3ie | Fence detector, QA ratio | MEDIUM |
| https://dev.to/cloudyview/how-i-fixed-llm-structured-output-failures-in-a-powerpoint-translator-0-errors-on-1214-20g | JSON / tool-use batching | MEDIUM |
| https://github.com/MicrosoftDocs/azure-ai-docs/blob/main/articles/ai-services/translator/document-translation/how-to-guides/create-use-glossaries.md | Glosarios, case, pares idioma | HIGH |

---

*Investigación pitfalls: 2026-05-28. Consumir junto con `.planning/research/SUMMARY.md` (orquestador) para implicaciones de fases en ROADMAP.*
