# NOTEBOOK — Roadmap de ampliaciones

Cuaderno de ideas para evolucionar **MarkDown Auto Translator**.  
Estado del proyecto al crear este documento: traductor web + API con OpenAI/DeepL, modos editor/archivo/lote, preservación de Markdown y código, comentarios `#` traducibles en bloques shell.

---

## Leyenda de prioridad

| Símbolo | Significado                             |
| ------- | --------------------------------------- |
| 🔴       | Alto impacto — recomendado empezar aquí |
| 🟡       | Calidad y confianza                     |
| 🟢       | Potencia «pro» / equipo / despliegue    |
| ⚙️      | Esfuerzo bajo                           |
| ⚙️⚙️    | Esfuerzo medio                          |
| ⚙️⚙️⚙️  | Esfuerzo alto                           |

---

## 1. Glosario y términos fijos 🔴 ⚙️⚙️

**Qué es**  
Diccionario de términos que el traductor debe respetar: no traducir, traducir siempre igual o sustituir por una forma acordada.

**Ejemplos**

- `API Gateway` → no traducir  
- `piece of cake` → `pan comido`  
- `MarkDown Auto Translator` → nombre de producto fijo  

**Implementación sugerida**

- Archivo `glossary.json` o `glossary.yaml` en la raíz del proyecto  
- Panel en la UI para añadir/editar entradas  
- Inyectar reglas en el prompt (OpenAI) o pre/post-procesado (DeepL + placeholders)  
- Soporte por idioma destino: `{ "en→es": { "dashboard": "panel" } }`

**Beneficio**  
Coherencia en documentación técnica y lotes grandes; menos revisiones manuales.

**Criterios de aceptación**

- [ ] Glosario cargable desde archivo y desde UI  
- [ ] Aplicado en editor, archivo único y lote  
- [ ] Entradas «no traducir» preservadas literalmente  

---

## 2. Memoria de traducción 🔴 ⚙️⚙️

**Qué es**  
Cache persistente de segmentos ya traducidos (hash del texto origen + idioma origen/destino → traducción).

**Implementación sugerida**

- SQLite (`data/translation_memory.db`) o archivos JSON por par de idiomas  
- Clave: `sha256(normalized_text + source_lang + target_lang)`  
- Invalidación manual o por TTL configurable  
- Estadísticas: % cache hit, tokens ahorrados  

**Beneficio**  
Menor coste de API, mayor velocidad y **misma frase traducida igual** en todos los archivos del lote.

**Criterios de aceptación**

- [ ] Cache consultada antes de cada llamada al proveedor  
- [ ] Nuevas traducciones se guardan automáticamente  
- [ ] Comando o botón «limpiar memoria»  

---

## 3. CLI para automatización 🔴 ⚙️⚙️

**Qué es**  
Interfaz de línea de comandos sin levantar el servidor web.

**Comandos propuestos**

```bash
md-translate file README.md -t es -o README.es.md
md-translate dir docs/ -t en -o docs-en/ --recursive
md-translate batch ./articles/*.md -t fr --zip out.zip
md-translate --provider deepl --source auto --target es input.md
```

**Implementación sugerida**

- Entry point en `pyproject.toml`: `md-translate = src.cli:main`  
- Reutilizar `parser`, `translator` y validación existentes  
- Salida con códigos de exit útiles para CI (0 OK, 1 error parcial, 2 error fatal)

**Beneficio**  
Integración en pipelines, scripts locales y uso sin navegador.

**Criterios de aceptación**

- [ ] Traducción de archivo y directorio  
- [ ] Mismas variables de entorno que la API  
- [ ] `--dry-run` para listar segmentos sin traducir  

---

## 4. Vista previa Markdown renderizada 🔴 ⚙️⚙️

**Qué es**  
Pestaña o panel que muestra el Markdown **renderizado** (HTML), no solo el texto plano.

**Implementación sugerida**

- Librería cliente: `marked.js` o similar en `static/`  
- Layout: Original | Traducción | Vista previa (o split original/preview vs traducción/preview)  
- Resaltar diferencias obvias (enlaces rotos, encabezados vacíos)

**Beneficio**  
Detectar visualmente tablas rotas, listas mal cerradas o enlaces antes de exportar.

**Criterios de aceptación**

- [ ] Preview sincronizado al pegar o al terminar traducción  
- [ ] Modo oscuro coherente con la UI  
- [ ] No ejecutar JS/HTML peligroso del MD (sanitizar)  

---

## 5. Progreso en tiempo real (lote) 🔴 ⚙️⚙️

**Qué es**  
Feedback en vivo durante traducción por lote: archivo actual, segmentos, porcentaje.

**Implementación sugerida**

- Endpoint SSE: `GET /api/translate/batch/stream` o WebSocket  
- Job ID + cola en memoria o Redis (si escala)  
- UI: barra de progreso por archivo y global  

**Beneficio**  
Lotes de 10–20 archivos dejan de ser «caja negra» con spinner indefinido.

**Criterios de aceptación**

- [ ] Eventos: `file_start`, `file_done`, `segment_progress`, `error`, `complete`  
- [ ] Cancelación de job en curso  
- [ ] Descarga ZIP al finalizar sin recargar página  

---

## 6. Validación post-traducción 🟡 ⚙️⚙️

**Qué es**  
Comprobaciones automáticas de que la traducción no rompió la estructura.

**Checks propuestos**

| Check         | Descripción                                                          |
| ------------- | -------------------------------------------------------------------- |
| Fences        | Mismo número de bloques fenced (triple backtick) abiertos y cerrados |
| Enlaces       | Misma cantidad de `[texto](url)` e `![alt](url)`                     |
| Código inline | Mismo número de spans con backticks inline                           |
| Encabezados   | Misma profundidad `#` por línea                                      |
| Longitud      | Alerta si un segmento creció >300 % (posible alucinación)            |

**Implementación sugerida**

- Módulo `src/validator.py` con informe JSON + resumen en UI  
- Nivel «warning» vs «error» (error bloquea descarga opcional)

**Criterios de aceptación**

- [ ] Informe visible tras traducir  
- [ ] Exportar informe en lote (JSON en el ZIP)  

---

## 7. Comentarios en más lenguajes de código 🟡 ⚙️⚙️

**Qué es**  
Extender la lógica actual de comentarios `#` en `bash` a otros fences.

| Lenguaje                                 | Comentario | Traducir            |
| ---------------------------------------- | ---------- | ------------------- |
| `bash`, `sh`, `zsh`                      | `#`        | ✅ (ya implementado) |
| `python`, `ruby`                         | `#`        | 🔲                   |
| `javascript`, `typescript`, `java`, `go` | `//`       | 🔲                   |
| `html`, `xml`                            | `<!-- -->` | 🔲                   |
| `sql`                                    | `--`       | 🔲                   |

**Precaución**  
No traducir URLs, shebangs, directivas pragma ni `#` dentro de strings.

**Criterios de aceptación**

- [ ] Detección por etiqueta del fence (` ```python `)  
- [ ] Tests por lenguaje  
- [ ] Comandos y literales intactos  

---

## 8. Frontmatter YAML selectivo 🟡 ⚙️⚙️

**Qué es**  
Traducir campos orientados al usuario en el frontmatter, preservar metadatos técnicos.

**Traducir**  
`title`, `description`, `summary`, `tags` (opcional)

**No traducir**  
`date`, `slug`, `id`, `layout`, `author`, URLs, booleanos, números

**Implementación sugerida**

- Parser YAML (PyYAML) sobre bloque `---` … `---`  
- Lista blanca/negra configurable en `.env` o `config.yaml`

**Criterios de aceptación**

- [ ] Frontmatter reconstruido con tipos YAML preservados  
- [ ] Fallback si YAML mal formado: bloque entero protegido  

---

## 9. Multi-destino en una pasada 🟢 ⚙️⚙️⚙️

**Qué es**  
Un solo upload genera varias versiones: `doc.es.md`, `doc.en.md`, `doc.fr.md` o ZIP multi-idioma.

**Implementación sugerida**

- UI: multi-select de idiomas destino  
- API: `target_langs: ["es", "en", "fr"]`  
- Paralelizar por idioma con límite de concurrencia (evitar rate limits)

**Criterios de aceptación**

- [ ] ZIP con estructura clara por idioma  
- [ ] Memoria de traducción compartida entre idiomas del mismo origen  

---

## 10. Estimación de coste y tokens 🟢 ⚙️

**Qué es**  
Antes de traducir, mostrar segmentos, caracteres aproximados y coste estimado.

**Implementación sugerida**

- Conteo tras `collect_translatable()`  
- Tabla de precios por proveedor/modelo en config (actualizable)  
- UI: «~70 segmentos · ~12 000 chars · ~$0.02 (gpt-4o-mini)»

**Criterios de aceptación**

- [ ] Endpoint `POST /api/translate/estimate`  
- [ ] Aviso si supera umbral configurable  

---

## 11. Docker y despliegue 🟢 ⚙️⚙️

**Qué es**  
Empaquetado reproducible para equipo o servidor interno.

**Archivos propuestos**

```text
Dockerfile
docker-compose.yml
.env.example → montado como .env
```

**Beneficio**  
Onboarding en un comando; despliegue en NAS, VPS o red local.

**Criterios de aceptación**

- [ ] Imagen < 200 MB si es posible (slim base)  
- [ ] Volumen para `output/` y memoria de traducción  
- [ ] Healthcheck en `/api/languages`  

---

## 12. Modo revisión (borrador) 🟢 ⚙️⚙️⚙️

**Qué es**  
Traducción editable segmento a segmento antes de exportar definitivo.

**Implementación sugerida**

- Lista de segmentos traducibles con textarea inline  
- Marcar segmentos «dudosos» (baja confianza heurística o flag del modelo)  
- Export solo cuando el usuario confirma  

**Beneficio**  
Flujo humano-en-el-bucle para docs críticas (legal, médica, release notes).

---

## 13. Proveedor con fallback ⚙️⚙️

**Qué es**  
Si DeepL falla (cuota, idioma no soportado), reintentar con OpenAI automáticamente.

**Config**

```env
TRANSLATION_PROVIDER=deepl
TRANSLATION_FALLBACK=openai
```

---

## 14. Diff visual original vs traducción ⚙️⚙️

**Qué es**  
Vista diff lado a lado o inline (solo texto traducible, código atenuado).

**Librería**  
`diff-match-patch` o componente diff en JS.

---

## 15. Carpeta vigilada (watch) ⚙️⚙️⚙️

**Qué es**  
Monitorizar `input/` y escribir traducciones en `output/` al guardar `.md`.

**Uso**  
Autores que editan en Obsidian, VS Code o iA Writer.

---

## 16. Traducción de árbol Git / docs site ⚙️⚙️⚙️

**Qué es**  
Subir carpeta o clonar repo docs; preservar estructura de directorios en el ZIP.

**Extra**  
Respetar `.gitignore` del proyecto fuente; omitir `node_modules`, etc.

---

## 17. Formal / informal (DeepL y LLM) ⚙️

**Qué es**  
Selector de registro: tuteo/voseo, usted, tono formal DeepL (`formality=more|less`).

**UI**  
Toggle «Tono: formal | informal | automático».

---

## 18. Historial de sesiones ⚙️⚙️

**Qué es**  
Lista de traducciones recientes en localStorage o servidor (sin contenido sensible por defecto).

**Privacidad**  
Opt-in; no guardar API keys; borrado fácil.

---

## 19. Export HTML/PDF además de MD ⚙️⚙️⚙️

**Qué es**  
Generar HTML autocontenido o PDF desde el Markdown traducido.

**Librerías**  
`markdown` + `weasyprint` o pandoc en CLI.

---

## 20. API key por usuario (multi-tenant) ⚙️⚙️⚙️

**Qué es**  
Si se expone públicamente: cada usuario aporta su clave (almacenada cifrada o solo en sesión).

**Solo si**  
Hay despliegue compartido; no necesario para uso local.

---

## Orden de implementación recomendado

| Fase  | Entregables                                 | Motivo                                |
| ----- | ------------------------------------------- | ------------------------------------- |
| **A** | Glosario + memoria de traducción + CLI      | Máximo ROI en docs técnicas y lotes   |
| **B** | Validación post-traducción + preview render | Confianza y menos errores silenciosos |
| **C** | Progreso SSE en lote + estimación de coste  | UX y control de gasto                 |
| **D** | Multi-destino + Docker                      | Equipo y despliegue                   |
| **E** | Modo revisión + watch + diff                | Flujo profesional editorial           |

---

## Notas técnicas del codebase actual

```text
src/parser.py      → Segmentación protegido / traducible
src/translator.py  → OpenAI + DeepL, lotes, reintentos
src/main.py        → FastAPI, editor / archivo / lote
static/            → UI Tailwind + Plus Jakarta Sans
```

**Puntos de extensión naturales**

- `parser.py`: frontmatter YAML, más lenguajes shell-like  
- `translator.py`: glosario en prompt, cache, fallback  
- `main.py`: SSE, estimate, multi-target  
- Nuevo `src/cli.py`, `src/glossary.py`, `src/memory.py`, `src/validator.py`  

---

## Ideas descartadas o para más adelante

- Traducción de PDF/DOCX directa (alcance distinto; mejor pipeline MD intermedio)  
- MT offline completo sin LLM (calidad inferior en modismos; DeepL/OpenAI siguen siendo mejores)  
- Plugin Obsidian/VS Code (útil pero otro repositorio o fase F)  

---

*Última actualización: 2026-05-28*
