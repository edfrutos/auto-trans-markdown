# MarkDown Auto Translator

Traductor de archivos Markdown que preserva el formato original, protege bloques de código y adapta el texto al usuario con traducción contextual (incluyendo expresiones coloquiales).

## Características

- **Cualquier idioma → idioma seleccionado** (30+ idiomas o detección automática); **multi-destino** en una pasada
- **Salida .md** lista para usar, con la misma estructura que el original; export **HTML** opcional
- **Código intacto**: bloques ` ``` `, inline `` ` ``, frontmatter YAML, bloques indentados
- **Formato preservado**: encabezados, listas, tablas, enlaces, imágenes, citas
- **Traducción contextual** vía LLM; **tono** auto / formal / informal; fallback DeepL → OpenAI
- **Glosario** (`glossary.yaml` + UI) y **memoria de traducción** SQLite (segmentos repetidos sin re-llamar API)
- **Validación** post-traducción (fences, enlaces, imágenes) y **preview** sanitizada (original + traducido)
- **Lote con SSE**: progreso real, cancelación, estimación de coste, ZIP parcial + `errors.json`
- **Modo revisión**: edición por segmentos, diff resaltado, historial opt-in (solo metadatos)
- **Tres modos web**: editor en vivo, archivo único, lote (ZIP)
- **CLI** `md-translate`: file, dir, batch, watch, export; respeta `.gitignore`
- **Docker** multi-stage + `docker-compose` para despliegue en equipo

## Requisitos

- Python 3.11+
- **OpenAI** (`OPENAI_API_KEY`) **o** **DeepL** (`DEEPL_API_KEY`) — según el proveedor elegido

## Instalación

```bash
cd auto-trans-markdown
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
pip install -e .            # Instala el comando md-translate en .venv/bin/
cp .env.example .env        # Edita y añade tu API key
```

## Uso

```bash
python -m src.main
```

Abre [http://127.0.0.1:5400](http://127.0.0.1:5400) en el navegador (puerto configurable con `PORT`).

### Multi-destino

Puedes traducir el mismo contenido a **varios idiomas** en una sola operación:

- **Web**: añade idiomas con el selector «Añadir idioma…» (chips); el estimate y el lote muestran el total agregado.
- **API**: envía `target_lang` (primer idioma, compatibilidad) y/o `target_langs` (lista). Salida en lote/ZIP: `stem.{lang}.md` y `stem.{lang}.validation.json`.
- **CLI**: `-t es,en,fr` en `file`, `dir` y `batch`.

Ejemplo API JSON:

```json
{
  "content": "# Hello",
  "target_langs": ["es", "en"],
  "source_lang": "auto",
  "tone": "auto"
}
```

`tone`: `auto` (default), `formal` o `informal`.

Respuesta multi-idioma: `{ "translations": { "es": { ... }, "en": { ... } } }`.

### Docker

```bash
cp .env.example .env   # configura OPENAI_API_KEY o DEEPL_API_KEY
docker compose up --build
```

La app escucha en **5400** (`http://localhost:5400`). Volúmenes: `./data` (memoria/glosario) y `./output` (descargas temporales).

En VPS o LAN, ajusta `CORS_ORIGINS` y `HOST=0.0.0.0` (ya en compose). Ver variables SEC en `.env.example`.

### API

| Método | Ruta | Descripción |
| ------ | ---- | ------------- |
| `GET` | `/api/languages` | Lista de idiomas (filtrada por proveedor activo) |
| `GET` | `/api/glossary` | Lee glosario (`glossary.yaml`) |
| `PUT` | `/api/glossary` | Actualiza glosario |
| `DELETE` | `/api/memory` | Vacía memoria de traducción SQLite |
| `POST` | `/api/translate` | Traduce JSON `{ content, target_lang?, target_langs?, source_lang, tone? }` |
| `POST` | `/api/translate/draft` | Borrador revisable (un solo idioma destino) |
| `POST` | `/api/translate/finalize` | Reensambla con ediciones `{ content, segments: {index: text} }` |
| `POST` | `/api/translate/file` | Sube un `.md` (form: `tone`, `target_langs`, …) |
| `POST` | `/api/translate/batch` | Sube varios archivos, devuelve ZIP (síncrono) |
| `POST` | `/api/translate/batch/jobs` | Crea job de lote con progreso SSE |
| `POST` | `/api/translate/estimate` | Estima segmentos, caracteres y coste |

Endpoints de traducción pueden requerir `Authorization: Bearer <API_TOKEN>` si `API_TOKEN` está configurado.

Documentación interactiva: [http://127.0.0.1:5400/docs](http://127.0.0.1:5400/docs)

## Configuración

Elige un proveedor con `TRANSLATION_PROVIDER`:

### OpenAI (por defecto) — mejor para Markdown + modismos

Ideal cuando quieres que el modelo **preserve sintaxis Markdown compleja** y **adapte expresiones coloquiales** con criterio contextual.

```env
TRANSLATION_PROVIDER=openai
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o-mini
# OPENAI_BASE_URL=   # opcional: Ollama, Azure, etc.
```

### DeepL — traducción neural de alta calidad

Usa la API oficial de DeepL. **No** pongas la clave DeepL en `OPENAI_API_KEY`; van en variables distintas.

```env
TRANSLATION_PROVIDER=deepl
DEEPL_API_KEY=tu-auth-key-deepl
# Plan gratuito:
DEEPL_API_URL=https://api-free.deepl.com
```

| Variable | Descripción |
| -------- | ----------- |
| `TRANSLATION_PROVIDER` | `openai` (default) o `deepl` |
| `OPENAI_API_KEY` | Clave OpenAI (solo si provider=openai) |
| `OPENAI_BASE_URL` | Endpoint alternativo (Ollama, Azure, etc.) |
| `OPENAI_MODEL` | Modelo (default: `gpt-4o-mini`) |
| `DEEPL_API_KEY` | Auth key de DeepL (solo si provider=deepl) |
| `DEEPL_API_URL` | `https://api-free.deepl.com` en plan Free |
| `TRANSLATION_FALLBACK` | `openai` — reintento con OpenAI si DeepL falla (requiere `OPENAI_API_KEY`) |
| `HOST` / `PORT` | Servidor web (default `127.0.0.1:5400`) |
| `ESTIMATE_WARN_USD` | Umbral USD para aviso de coste estimado (default: `1.0`) |
| `CORS_ORIGINS` | Orígenes permitidos separados por coma (default localhost:5400) |
| `MAX_UPLOAD_MB` / `MAX_BATCH_UPLOAD_MB` | Límites de subida por archivo y lote |
| `OUTPUT_TTL_HOURS` / `OUTPUT_SWEEP_INTERVAL_HOURS` | Limpieza de `output/` |
| `API_TOKEN` | Bearer opcional para proteger endpoints de traducción |

**Nota:** DeepL no soporta todos los idiomas de la lista (p. ej. catalán, gallego, euskera). Para esos casos usa OpenAI.

### Batch jobs (SSE)

Traducción por lote **asíncrona** con progreso en tiempo real (Server-Sent Events):

| Método | Ruta | Descripción |
| ------ | ---- | ----------- |
| `POST` | `/api/translate/batch/jobs` | Crea job; responde `{ job_id }` |
| `GET` | `/api/translate/batch/jobs/{job_id}/events` | Stream SSE (`file_start`, `segment_progress`, `file_done`, `error`, `complete`) |
| `DELETE` | `/api/translate/batch/jobs/{job_id}` | Cancelación cooperativa |
| `GET` | `/api/translate/batch/jobs/{job_id}/download` | ZIP con traducciones (y `errors.json` si hubo fallos) |

El endpoint síncrono `POST /api/translate/batch` sigue disponible para lotes pequeños sin SSE.

### Cost estimate

Antes de traducir un archivo o lote grande:

| Método | Ruta | Descripción |
| ------ | ---- | ----------- |
| `POST` | `/api/translate/estimate` | JSON `{ content, target_lang?, target_langs?, source_lang? }` o multipart `files[]` |

Respuesta: `segments`, `characters`, `estimated_cost_usd`, `provider`, `model`, `exceeds_threshold`, `threshold_usd`, `language_count`.

Configura el umbral con `ESTIMATE_WARN_USD` en `.env` (ver `.env.example`).

## Tests

```bash
pip install pytest
pytest tests/ -q
```

## CLI

Tras `pip install -e .` (con el venv activado), puedes usar:

```bash
md-translate file README.md -t es -o README.es.md
```

**Sin activar `.venv`**, desde la raíz del repo:

```bash
./scripts/md-translate --help
./scripts/md-translate file README.md -t es --dry-run
```

Opcional: añade `export PATH="/ruta/al/proyecto/scripts:$PATH"` en tu shell para invocar `md-translate` desde cualquier directorio.

```bash
md-translate file README.md -t es -o README.es.md
md-translate file README.md -t es,en,fr
md-translate dir docs/ -t en -o docs-en/ --recursive
md-translate batch ./articles/*.md -t fr,de --zip out.zip
md-translate dir docs/ -t en -o docs-en/ --recursive --respect-gitignore
md-translate watch docs/ -o docs-en/ -t es
md-translate export README.es.md -o README.es.html
md-translate file doc.md -t es --tone formal
md-translate file doc.md -t es --dry-run
md-translate memory clear
md-translate serve
```

### Flujo editorial (web)

- **Tono:** selector Auto / Formal / Informal (DeepL `formality`, hint OpenAI).
- **Modo revisión:** borrador por segmentos con marcado de dudosos; confirmar vía `/api/translate/finalize`.
- **Diff:** pestaña Diff con resaltado por segmento (`diff-match-patch`).
- **Historial:** opt-in en localStorage (solo metadatos: idioma, modo, fecha).
- **Export HTML:** botón en UI o `md-translate export`.

Variables opcionales: `TRANSLATION_FALLBACK=openai` (DeepL → OpenAI si falla cuota/idioma). Ver `.env.example`.

Glosario por defecto en `glossary.yaml`; memoria SQLite en `data/translation_memory.db` (gitignored).

## Arquitectura

```sh
src/parser.py      → Segmenta MD (protegido vs traducible)
src/pipeline.py    → Fachada translate_markdown (TM + glosario)
src/translator.py  → Traducción por lotes (OpenAI o DeepL)
src/memory.py      → Memoria de traducción SQLite
src/glossary.py    → Glosario YAML
src/cli.py         → CLI Typer md-translate
src/review.py      → Modo revisión draft/finalize
src/gitignore_filter.py → Filtro .gitignore para dir/batch
src/html_export.py → Export Markdown → HTML autocontenido
src/main.py        → API FastAPI + archivos estáticos
static/            → Interfaz web (Tailwind + Plus Jakarta Sans)
```

## Licencia

MIT
