# MarkDown Auto Translator

Traductor de archivos Markdown que preserva el formato original, protege bloques de código y adapta el texto al usuario con traducción contextual (incluyendo expresiones coloquiales).

## Características

- **Cualquier idioma → idioma seleccionado** (30+ idiomas o detección automática)
- **Salida .md** lista para usar, con la misma estructura que el original
- **Código intacto**: bloques ` ``` `, inline `` ` ``, frontmatter YAML, bloques indentados
- **Formato preservado**: encabezados, listas, tablas, enlaces, imágenes, citas
- **Traducción contextual** vía LLM: modismos y frases naturales, no literal palabra a palabra
- **Tres modos**: editor en vivo, archivo único, lote (ZIP)

## Requisitos

- Python 3.11+
- **OpenAI** (`OPENAI_API_KEY`) **o** **DeepL** (`DEEPL_API_KEY`) — según el proveedor elegido

## Instalación

```bash
cd auto-trans-markdown
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env        # Edita y añade tu API key
```

## Uso

```bash
python -m src.main
```

Abre [http://127.0.0.1:8000](http://127.0.0.1:8000) en el navegador.

### API

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/api/languages` | Lista de idiomas |
| `POST` | `/api/translate` | Traduce texto JSON `{ content, target_lang, source_lang }` |
| `POST` | `/api/translate/file` | Sube un `.md` y devuelve el archivo traducido |
| `POST` | `/api/translate/batch` | Sube varios archivos, devuelve ZIP |

Documentación interactiva: [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs)

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
|----------|-------------|
| `TRANSLATION_PROVIDER` | `openai` (default) o `deepl` |
| `OPENAI_API_KEY` | Clave OpenAI (solo si provider=openai) |
| `OPENAI_BASE_URL` | Endpoint alternativo (Ollama, Azure, etc.) |
| `OPENAI_MODEL` | Modelo (default: `gpt-4o-mini`) |
| `DEEPL_API_KEY` | Auth key de DeepL (solo si provider=deepl) |
| `DEEPL_API_URL` | `https://api-free.deepl.com` en plan Free |
| `HOST` / `PORT` | Servidor web |

**Nota:** DeepL no soporta todos los idiomas de la lista (p. ej. catalán, gallego, euskera). Para esos casos usa OpenAI.

## Tests

```bash
pip install pytest
pytest tests/ -q
```

## Arquitectura

```
src/parser.py      → Segmenta MD (protegido vs traducible)
src/translator.py  → Traducción por lotes (OpenAI o DeepL)
src/main.py        → API FastAPI + archivos estáticos
static/            → Interfaz web (Tailwind + Plus Jakarta Sans)
```

## Licencia

MIT
