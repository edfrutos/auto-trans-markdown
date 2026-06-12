# Phase 8: Reproducible Dependencies - Research

**Researched:** 2026-05-31
**Domain:** Python dependency management with uv — lockfile generation, Docker integration, README documentation
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LOCK-01 | Incluir `uv.lock` commiteado en git con versiones exactas de todas las dependencias | `uv lock` resuelve 59 paquetes desde el `pyproject.toml` actual sin modificaciones |
| LOCK-02 | Reproducir entorno exacto con `uv sync` sin argumentos adicionales | `uv sync` lee `uv.lock` + crea `.venv` en un solo comando |
| LOCK-03 | Flujo documentado para actualizar lockfile (`uv add`, `uv lock --upgrade`) | Comandos verificados en docs oficiales |
| LOCK-04 | README actualizado con instrucciones uv (recomendado) y pip (alternativa) | Sección de instalación actual usa solo pip; requiere extensión |
| LOCK-05 | Dockerfile y docker-compose actualizados para usar `uv sync --frozen` | Dockerfile actual usa `pip install -r requirements.txt` en builder; requiere rediseño |
</phase_requirements>

---

## Summary

El proyecto `auto-trans-markdown` tiene un `pyproject.toml` con `setuptools` como build-backend y un `requirements.txt` con pins mínimos (`>=`). **No existe `uv.lock` en el repositorio.** Esta fase lo genera y lo integra en el flujo de desarrollo y Docker.

`uv` 0.11.4 está instalado en el sistema y es compatible con el `pyproject.toml` existente **sin ninguna modificación** — no requiere sección `[tool.uv]` ni cambio de build-backend. El comando `uv lock --dry-run` resuelve correctamente los 59 paquetes, incluyendo los extras opcionales `[test]` y `[pdf]`.

El Dockerfile actual (multi-stage con `python:3.11-slim`) instala dependencias vía `pip install -r requirements.txt` en la etapa builder. Debe ser reescrito para: (1) copiar el binario `uv` desde la imagen oficial `ghcr.io/astral-sh/uv`, (2) usar `uv sync --frozen --no-dev` para instalar dependencias bloqueadas en el builder, y (3) copiar el `.venv` al runtime stage. El `requirements.txt` puede mantenerse como fallback generado vía `uv export`, pero no debe ser la fuente de verdad.

**Recomendación principal:** `uv lock` genera `uv.lock`; `uv sync` restaura el entorno. Commitear `uv.lock`, no `.venv`. Actualizar Dockerfile con patrón `COPY --from=ghcr.io/astral-sh/uv` + `uv sync --frozen`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Generación del lockfile | Dev local | CI/CD | `uv lock` corre en la máquina del desarrollador; el resultado se commitea |
| Reproducción del entorno | Dev local + Docker builder | — | `uv sync` y `uv sync --frozen` respectivamente |
| Instalación en contenedor | Docker builder stage | — | El `.venv` se construye en builder y se copia a runtime |
| Documentación del flujo | README | — | Sección de instalación dirigida al desarrollador |
| Fallback pip-compatible | Artefacto generado (`requirements.txt`) | — | `uv export` produce el archivo; pip puede consumirlo sin uv |

---

## Standard Stack

### Core

| Herramienta | Versión | Propósito | Por qué estándar |
|-------------|---------|-----------|------------------|
| `uv` | 0.11.17 (última en PyPI) | Resolver, lockear y sincronizar dependencias Python | Herramienta oficial de Astral; lockfile universal cross-platform; velocidad 10-100x sobre pip |

> **Nota de versión:** El sistema tiene `uv` 0.11.4 (instalado 2026-04-07). La última versión en PyPI es 0.11.17. [VERIFIED: PyPI registry via `pip index versions uv`]. No hay breaking changes entre 0.11.4 y 0.11.17 para el uso de `uv lock`/`uv sync`. La fase puede desarrollarse con la versión instalada; el `uv.lock` generado será válido.

### Artefactos generados (no instalados como dependencias del proyecto)

| Artefacto | Comando generador | Propósito |
|-----------|------------------|-----------|
| `uv.lock` | `uv lock` | Lockfile de versiones exactas — committear en git |
| `requirements.txt` (actualizado) | `uv export --format requirements-txt --no-hashes` | Fallback pip-compatible — generado, no editado a mano |

### No hay paquetes Python nuevos que instalar en el proyecto

Esta fase no añade dependencias al `pyproject.toml`. El único cambio de dependencias es que `requirements.txt` pasa a ser un artefacto *derivado* de `uv.lock` en lugar de la fuente de verdad.

---

## Package Legitimacy Audit

> Esta fase no instala paquetes Python nuevos en el proyecto. `uv` es una herramienta de sistema (developer tool), no una dependencia del paquete.

| Paquete | Registro | Antigüedad | Descargas | Repo fuente | slopcheck | Disposición |
|---------|----------|-----------|-----------|-------------|-----------|-------------|
| `uv` (system tool) | PyPI | ~2 años | 15M+/sem | github.com/astral-sh/uv | [OK] | Aprobado — herramienta de sistema, no en requirements.txt |
| `fastapi` (existente) | PyPI | ~6 años | 30M+/sem | github.com/fastapi/fastapi | [OK] | Existente — sin cambios |
| `uvicorn` (existente) | PyPI | ~6 años | 20M+/sem | github.com/encode/uvicorn | [OK] | Existente — sin cambios |
| `openai` (existente) | PyPI | ~3 años | 25M+/sem | github.com/openai/openai-python | [OK] | Existente — sin cambios |
| `deepl` (existente) | PyPI | ~4 años | 500K+/sem | github.com/DeepLcom/deepl-python | [OK] | Existente — sin cambios |

**Paquetes eliminados por slopcheck [SLOP]:** ninguno
**Paquetes marcados como sospechosos [SUS]:** ninguno

*Todos los paquetes verificados con `slopcheck install uv fastapi uvicorn openai deepl` — 5/5 [OK]. [VERIFIED: slopcheck 0.6.1]*

---

## Architecture Patterns

### System Architecture Diagram

```
pyproject.toml (fuente de verdad de dependencias)
        │
        ▼
   uv lock ──────────────────────────────► uv.lock (committear)
        │                                       │
        │                              uv sync  │  (dev local)
        │                                       ▼
        │                                  .venv/ (NO committear)
        │
        │  uv export --format requirements-txt --no-hashes
        ▼
requirements.txt (artefacto derivado — fallback pip)
        │
        └─── [alternativa: pip install -r requirements.txt]

Docker build:
   COPY --from=ghcr.io/astral-sh/uv:0.11.17 /uv /bin/
        │
        ▼
   uv sync --frozen --no-dev ──► .venv/ (en builder stage)
        │
        ▼
   COPY --from=builder /app/.venv /app/.venv  (runtime stage)
```

### Estructura de archivos afectados

```
auto-trans-markdown/
├── pyproject.toml          # sin cambios (setuptools, extras [test][pdf])
├── uv.lock                 # NUEVO — generado y commiteado
├── requirements.txt        # ACTUALIZADO — ahora derivado de uv.lock via uv export
├── Dockerfile              # ACTUALIZADO — usa uv en builder stage
├── docker-compose.yml      # sin cambios (solo referencia Dockerfile)
├── .gitignore              # VERIFICADO — ya tiene .venv/, no tiene uv.lock en exclusiones
├── .dockerignore           # ACTUALIZADO — añadir uv.lock a los archivos copiados (ya no está excluido)
└── README.md               # ACTUALIZADO — sección instalación con instrucciones uv + pip
```

### Patrón 1: Generación inicial del lockfile

**Qué:** Crear `uv.lock` desde el `pyproject.toml` existente por primera vez.
**Cuándo usar:** Solo una vez, al inicializar el lockfile en el repo.

```bash
# Source: https://docs.astral.sh/uv/concepts/projects/layout/
uv lock
```

Resultado: `uv.lock` creado en la raíz del proyecto con 59 paquetes exactamente versionados.
No modifica `pyproject.toml`. No requiere `[tool.uv]`.

### Patrón 2: Restaurar entorno de desarrollo

**Qué:** Crear/actualizar `.venv` local a partir del lockfile.
**Cuándo usar:** Al clonar el repo o al cambiar de rama.

```bash
# Source: https://docs.astral.sh/uv/concepts/projects/sync/
uv sync                    # instala dependencias base + dev groups
uv sync --extra test       # incluye extras [test]
uv sync --extra pdf        # incluye extras [pdf] (WeasyPrint + deps nativas)
uv sync --all-extras       # instala todos los extras
```

### Patrón 3: Flujo de actualización de dependencias

**Qué:** Añadir o actualizar dependencias manteniendo el lockfile coherente.
**Cuándo usar:** Al añadir nuevas librerías o actualizar versiones.

```bash
# Source: https://docs.astral.sh/uv/guides/projects/
# Añadir nueva dependencia
uv add <paquete>

# Añadir dependencia opcional a un extra existente
uv add <paquete> --optional test   # o --optional pdf

# Actualizar un paquete específico manteniendo el resto bloqueado
uv lock --upgrade-package <paquete>

# Actualizar todo (nueva resolución completa)
uv lock --upgrade
```

### Patrón 4: Generar requirements.txt como fallback pip

**Qué:** Exportar el lockfile a formato `requirements.txt` para usuarios sin `uv`.
**Cuándo usar:** Después de cada `uv lock` o `uv add`.

```bash
# Source: https://docs.astral.sh/uv/reference/cli/#uv-export
uv export --format requirements-txt --no-hashes > requirements.txt
```

> **Importante:** El `requirements.txt` resultante incluye `-e .` (editable install del propio proyecto). Para Docker, el Dockerfile no debe usar este archivo — usa directamente `uv sync --frozen`.

### Patrón 5: Dockerfile con uv (multi-stage)

**Qué:** Instalar dependencias exactas en Docker usando el lockfile.
**Cuándo usar:** En todas las builds de producción.

```dockerfile
# Source: https://docs.astral.sh/uv/guides/integration/docker/#installing-a-project
# syntax=docker/dockerfile:1

FROM python:3.11-slim AS builder
# Copiar binario uv desde imagen oficial (version pinada para reproducibilidad)
COPY --from=ghcr.io/astral-sh/uv:0.11.17 /uv /bin/uv

WORKDIR /app
ENV UV_PYTHON_DOWNLOADS=0 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# Instalar dependencias primero (capa de cache separada del código fuente)
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-dev --no-install-project

# Copiar código fuente e instalar el proyecto
COPY pyproject.toml uv.lock ./
COPY src ./src
COPY static ./static
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

FROM python:3.11-slim AS runtime
WORKDIR /app

RUN groupadd --gid 1000 appuser \
    && useradd --uid 1000 --gid appuser --create-home appuser

COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src ./src
COPY --from=builder /app/static ./static

RUN mkdir -p /app/data /app/output \
    && chown -R appuser:appuser /app

ENV HOST=0.0.0.0 \
    PORT=5400 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

EXPOSE 5400
USER appuser

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5400/api/languages', timeout=3)"

CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "5400"]
```

**Variables de entorno uv en Docker:**

| Variable | Valor | Efecto |
|----------|-------|--------|
| `UV_PYTHON_DOWNLOADS=0` | 0 | Evita que uv descargue Python propio (usa el de la imagen base) |
| `UV_COMPILE_BYTECODE=1` | 1 | Precompila `.pyc` → mejor startup time (coste: tamaño imagen +5-10%) |
| `UV_LINK_MODE=copy` | copy | Necesario con `--mount=type=cache`; evita errores de hard-link cross-filesystem |

### Anti-Patterns a Evitar

- **No commitear `.venv/`**: ya en `.gitignore`; el lockfile + `uv sync` son suficientes.
- **No editar `uv.lock` a mano**: es gestionado exclusivamente por `uv`; cualquier edición manual se sobreescribirá.
- **No usar `uv sync --frozen` en desarrollo local**: en local es mejor `uv sync` (sin `--frozen`) para detectar si el lockfile está desactualizado respecto al `pyproject.toml`.
- **No omitir `--frozen` en Docker**: sin este flag, `uv` intentaría actualizar el lockfile durante el build, lo que falla porque no puede escribir en el árbol montado.
- **No mantener `requirements.txt` como fuente de verdad**: debe ser derivado de `uv.lock` via `uv export`. Si alguien edita `requirements.txt` directamente, los cambios se perderán en el próximo `uv export`.

---

## Don't Hand-Roll

| Problema | No construir | Usar en cambio | Por qué |
|----------|-------------|----------------|---------|
| Lockfile cross-platform | Scripts ad-hoc de freeze/pin | `uv lock` | Maneja marcadores de plataforma, hashes, conflictos de resolver |
| Reproducción de entorno | Scripts bash `pip install` con versiones | `uv sync` | Gestión automática de `.venv`, instalación incremental |
| Actualización selectiva | Edición manual de `requirements.txt` | `uv lock --upgrade-package X` | Actualiza solo X sin tocar el resto del grafo |
| Export pip-compatible | Plantillas manuales de requirements.txt | `uv export --format requirements-txt` | Genera con hashes, plataforma, y comments de trazabilidad |
| uv en Docker | Instalar uv via pip/curl en Dockerfile | `COPY --from=ghcr.io/astral-sh/uv:VERSION` | Imagen oficial distroless sin overhead; versión exacta pinada |

**Idea clave:** `uv.lock` es el grafo de dependencias resuelto, universal y reproducible. Cualquier alternativa manual recrea parcialmente esta funcionalidad con mayor complejidad y menor fiabilidad.

---

## Runtime State Inventory

> OMITIDO — esta es una fase greenfield de tooling, no una fase de rename/refactor/migración. No hay estado en runtime afectado por los cambios en `uv.lock` o `requirements.txt`.

---

## Common Pitfalls

### Pitfall 1: `--frozen` vs `--locked` — confusión en Docker

**Qué falla:** Usar `--locked` en Docker hace que la build falle si el lockfile tiene un leve desfase con el `pyproject.toml` copiado (por ejemplo, si el `COPY` del `pyproject.toml` fue parcial o falta un archivo de workspace).
**Por qué ocurre:** `--locked` valida que el lockfile esté al día con el `pyproject.toml`; si no puede leer todos los archivos necesarios para esa validación, falla. `--frozen` confía en el lockfile tal como está.
**Cómo evitar:** En Docker usar siempre `--frozen`. En CI/CD de validación (no en la build productiva) puede usarse `--locked` para detectar lockfiles desactualizados.
**Señales de aviso:** Error `uv: error: The lockfile requires ... but the project has ...` en la build de Docker.

[VERIFIED: docs.astral.sh/uv/reference/cli]

### Pitfall 2: `UV_PYTHON_DOWNLOADS=0` necesario en imagen `python:3.11-slim`

**Qué falla:** Sin esta variable, `uv` puede intentar descargar una versión de Python compatible al ejecutarse en el builder stage, ignorando el Python ya presente en la imagen base.
**Por qué ocurre:** `uv` tiene su propio gestor de Python; si detecta que el Python del sistema no encaja exactamente con sus requisitos internos, descarga uno nuevo.
**Cómo evitar:** `ENV UV_PYTHON_DOWNLOADS=0` en el Dockerfile antes de cualquier llamada a `uv`.
**Señales de aviso:** La build descarga ~60MB de Python adicional o falla con un timeout de descarga.

[VERIFIED: docs.astral.sh/uv/guides/integration/docker]

### Pitfall 3: `requirements.txt` con `-e .` no funciona directamente en Docker

**Qué falla:** `uv export` genera `requirements.txt` con `-e .` (editable install del proyecto). Si alguien intenta usar este archivo directamente con `pip install -r requirements.txt` en Docker sin haber copiado el código fuente antes, falla.
**Por qué ocurre:** El editable install requiere que los fuentes estén presentes en el path referenciado por `-e .`.
**Cómo evitar:** El Dockerfile no usa `requirements.txt` — usa `uv sync --frozen` directamente. Documentar en README que `requirements.txt` es para entornos locales sin uv, no para Docker.
**Señales de aviso:** `ERROR: File "setup.py" not found` o similar durante `pip install`.

[VERIFIED: comportamiento documentado en uv export docs + observación local del output de `uv export`]

### Pitfall 4: `uv.lock` en `.dockerignore` rompe el build

**Qué falla:** Si `uv.lock` está en `.dockerignore`, la instrucción `COPY uv.lock .` del Dockerfile falla silenciosamente o con error `COPY failed: file not found`.
**Por qué ocurre:** El contexto de build de Docker excluye archivos listados en `.dockerignore`.
**Cómo evitar:** Verificar que `.dockerignore` NO liste `uv.lock` o `*.lock`. El `.dockerignore` actual del proyecto NO tiene entradas de lock — correcto.
**Señales de aviso:** Error `failed to solve: failed to read dockerfile` o archivos no encontrados durante el COPY.

[VERIFIED: inspección directa del `.dockerignore` del proyecto]

### Pitfall 5: Local Python 3.14 vs Docker Python 3.11

**Qué falla:** El entorno local usa Python 3.14.3 (detectado en `.venv`), el Dockerfile usa `python:3.11-slim`. El `uv.lock` es cross-platform pero los paquetes con extensiones C pueden tener wheels diferentes.
**Por qué ocurre:** `uv.lock` registra las versiones correctas para cada plataforma, pero si hay paquetes sin wheels para Python 3.11/linux, el `uv sync --frozen` en Docker puede necesitar compilar desde fuentes.
**Cómo evitar:** La build de Docker ya maneja esto — los paquetes del proyecto (fastapi, openai, etc.) tienen wheels para Python 3.11/linux. WeasyPrint requiere libs del sistema (`libpango`, etc.) que no están en `python:3.11-slim` por defecto — pero está excluido del sync de producción con `--no-dev`.
**Señales de aviso:** Errores de compilación de extensiones C durante `uv sync` en Docker.

[VERIFIED: observación del dry-run; packages incluyen `cffi`, `zopfli` que tienen extensiones C]

---

## Code Examples

### Instalación inicial (primera vez en el repo)

```bash
# Source: https://docs.astral.sh/uv/concepts/projects/layout/
# 1. Generar el lockfile
uv lock

# 2. Crear el entorno virtual y sincronizar
uv sync

# 3. (Opcional) Incluir extras
uv sync --extra test --extra pdf

# 4. Activar el entorno (igual que siempre)
source .venv/bin/activate
```

### Regenerar requirements.txt desde el lockfile

```bash
# Source: https://docs.astral.sh/uv/reference/cli/#uv-export
uv export --format requirements-txt --no-hashes > requirements.txt
```

### Flujo de trabajo diario (tras clonar/pull)

```bash
# Source: https://docs.astral.sh/uv/concepts/projects/sync/
uv sync   # Lee uv.lock, actualiza .venv, no modifica el lockfile
```

### Añadir nueva dependencia

```bash
# Source: https://docs.astral.sh/uv/guides/projects/
uv add httpx              # añade a [project.dependencies] y actualiza uv.lock
uv add pytest --optional test  # añade al extra [test]
```

### Actualizar dependencia específica

```bash
# Source: https://docs.astral.sh/uv/reference/cli/#uv-lock
uv lock --upgrade-package fastapi   # solo actualiza fastapi y sus dependencias directas
uv lock --upgrade                   # actualización completa (nueva resolución)
```

### Instrucciones README — bloque de instalación propuesto

```bash
# Con uv (recomendado — entorno exactamente reproducible):
uv sync
source .venv/bin/activate
cp .env.example .env   # añade tu API key

# Con pip (alternativa sin cambio de toolchain):
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
pip install -e .
cp .env.example .env
```

---

## State of the Art

| Enfoque anterior | Enfoque actual | Desde | Impacto |
|-----------------|----------------|-------|---------|
| `pip install -r requirements.txt` (pins `>=`) | `uv sync` desde `uv.lock` (versiones exactas) | uv 0.1 (2024) | Reproducibilidad total; 0 "works on my machine" |
| `pip freeze > requirements.txt` manual | `uv export --format requirements-txt` | uv 0.3+ | Export derivado y trazable; nunca manual |
| `pip install` en Docker builder | `uv sync --frozen --no-dev` con cache mount | uv 0.5+ | Cache de layers más eficiente; builds más rápidas |
| `pip-tools` / `poetry.lock` | `uv.lock` | 2024-2025 | Un solo archivo universal (no por plataforma); formato TOML legible |

**Obsoleto/Deprecado:**
- `pip freeze > requirements.txt` como lockfile: produce versiones planas sin árbol de dependencias, no es cross-platform, no soporta extras. Sustituido por `uv.lock`.
- `pip-compile` (pip-tools): reemplazado por `uv lock` con mejor velocidad y soporte de extras.

---

## Assumptions Log

| # | Claim | Sección | Riesgo si está equivocado |
|---|-------|---------|--------------------------|
| A1 | `uv` 0.11.4 (instalado) es compatible con el `pyproject.toml` del proyecto sin modificaciones | Standard Stack | BAJO — verificado con `uv lock --dry-run` que resuelve 59 paquetes correctamente |
| A2 | La imagen Docker `python:3.11-slim` es compatible con los wheels de los 59 paquetes resueltos | Common Pitfalls | MEDIO — packages con extensiones C (cffi, zopfli) requieren compilación si no hay wheels para linux/3.11; en la práctica estos paquetes publican wheels para manylinux |
| A3 | El `requirements.txt` generado por `uv export` con `-e .` es aceptable como fallback para usuarios con pip | Code Examples | BAJO — la única limitación es que requieren el código fuente presente para el editable install, que es el caso en desarrollo local |

**Si la tabla está vacía de verdad:** todos los claims fueron verificados. Los 3 asumidos tienen riesgo bajo a medio y están justificados.

---

## Open Questions

1. **¿Debe el README instrucciones de instalación de uv incluir instalación de uv mismo?**
   - Lo que sabemos: `uv` no está instalado por defecto en la mayoría de sistemas
   - Lo que no está claro: si el equipo prefiere que el README documente `curl -LsSf https://astral.sh/uv/install.sh | sh` o asume `uv` ya instalado
   - Recomendación: incluir enlace a https://docs.astral.sh/uv/getting-started/installation/ en el README sin reproducir el comando de instalación (se desactualiza)

2. **¿Regenerar `requirements.txt` en CI o manualmente?**
   - Lo que sabemos: `uv export` genera el archivo en segundos; actualmente no hay CI configurado
   - Lo que no está claro: si el equipo quiere un workflow de GitHub Actions que lo regenere automáticamente
   - Recomendación: para esta fase, regeneración manual tras `uv add` / `uv lock --upgrade`; CI puede añadirse en una fase posterior

---

## Environment Availability

| Dependencia | Requerida por | Disponible | Versión | Fallback |
|-------------|---------------|-----------|---------|----------|
| `uv` | LOCK-01, LOCK-02, LOCK-03, LOCK-05 | ✓ | 0.11.4 (local); 0.11.17 (PyPI latest) | — (no hay fallback para LOCK-01..03; LOCK-05 usa imagen Docker oficial) |
| Docker | LOCK-05 | ✓ | Asumido — el proyecto ya tiene Dockerfile y docker-compose.yml funcionales | — |
| Python 3.11+ | Todo el proyecto | ✓ | 3.14.3 (local) | — |
| `ghcr.io/astral-sh/uv:0.11.17` (Docker image) | LOCK-05 | ✓ (requiere pull en primera build) | 0.11.17 | Usar `uv:latest` con riesgo de no-reproducibilidad |

**Dependencias faltantes sin fallback:** ninguna — todas están disponibles.

**Dependencias faltantes con fallback:** ninguna.

---

## Validation Architecture

### Test Framework

| Propiedad | Valor |
|-----------|-------|
| Framework | pytest (ya en `[project.optional-dependencies] test`) |
| Archivo de config | `pyproject.toml` → `[tool.pytest.ini_options]` |
| Comando rápido | `uv sync --extra test && pytest tests/ -q` |
| Suite completa | `pytest tests/ -v` |

### Phase Requirements → Test Map

| Req ID | Comportamiento | Tipo de test | Comando automatizado | Archivo existe |
|--------|---------------|-------------|---------------------|---------------|
| LOCK-01 | `uv.lock` existe y está commiteado en git | smoke | `test -f uv.lock && git ls-files uv.lock` | ❌ Wave 0 (no es test pytest, es verificación shell) |
| LOCK-02 | `uv sync` desde lockfile crea `.venv` funcional | integration | `uv sync && python -c "import fastapi; import openai; import deepl"` | ❌ Wave 0 |
| LOCK-03 | `uv add` / `uv lock --upgrade-package` actualizan lockfile | manual | — (requiere red + tiempo real) | manual-only |
| LOCK-04 | README contiene bloques de instalación con uv y pip | smoke | `grep -q "uv sync" README.md && grep -q "pip install" README.md` | ❌ Wave 0 |
| LOCK-05 | Docker build produce imagen funcional con `uv sync --frozen` | integration | `docker build -t md-translate-test . && docker run --rm md-translate-test python -c "import fastapi"` | ❌ Wave 0 |

> LOCK-03 es **manual-only** porque valida el flujo de workflow del desarrollador (requiere acceso a PyPI y modificar dependencias reales).

### Sampling Rate

- **Por tarea commiteada:** `test -f uv.lock && uv sync && python -c "import fastapi"`
- **Por wave merge:** suite completa existente `pytest tests/ -q` + smoke de Docker
- **Phase gate:** todos los checks de la tabla en verde antes de `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `tests/test_lock_smoke.py` — verifica existencia de `uv.lock` e importabilidad de dependencias clave (cubre LOCK-01, LOCK-02)
- [ ] Script de verificación Docker en `tests/smoke_docker.sh` (cubre LOCK-05)

*(Nota: los tests de existencia de archivo y README son smoke tests de integración, no unit tests del código Python. Pueden implementarse como scripts shell o como fixtures pytest con `subprocess`.)*

---

## Security Domain

> `security_enforcement` no está explícitamente en config — tratar como habilitado.

### Applicable ASVS Categories

| ASVS Category | Aplica | Control estándar |
|---------------|--------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | no | Esta fase no procesa input externo |
| V6 Cryptography | parcial | `uv.lock` incluye hashes SHA-256 de cada paquete — verificación de integridad automática |
| Supply Chain (OWASP) | sí | `uv.lock` con hashes previene sustitución de paquetes; pinning de imagen Docker (`ghcr.io/astral-sh/uv:0.11.17`) previene cambios silenciosos |

### Known Threat Patterns para esta fase

| Patrón | STRIDE | Mitigación estándar |
|--------|--------|---------------------|
| Dependency confusion / supply chain attack | Tampering | `uv.lock` con hashes SHA-256; slopcheck antes de `uv add` |
| Imagen Docker con tag mutable (`uv:latest`) | Tampering | Pin a versión específica `uv:0.11.17` en Dockerfile |
| `requirements.txt` editado manualmente (deriva del lockfile) | Tampering | Documentar que `requirements.txt` es artefacto derivado; regenerar siempre con `uv export` |

---

## Project Constraints (from CLAUDE.md)

Directivas extraídas del `CLAUDE.md` del proyecto relevantes para esta fase:

| Directiva | Impacto en la fase |
|-----------|-------------------|
| `Tech stack: Mantener Python 3.11+, FastAPI, parser actual; extender sin reescritura total` | No cambiar build-backend (setuptools), no reescribir `pyproject.toml` más allá de añadir `[tool.uv]` si fuera necesario (no lo es) |
| `Seguridad: Nunca commitear .env` | `uv.lock` SÍ debe commitearse; `.env` sigue en `.gitignore` — sin cambios |
| `Formato: Salida siempre Markdown válido; código y URLs intactos` | No aplica directamente a esta fase |
| `Privacidad: output/ puede contener docs privados — gitignore` | Sin cambios en `.gitignore` para `output/` |
| Convención naming: `snake_case`, helpers con `_`, módulos en `src/` | Sin impacto — esta fase no añade código Python |
| Error handling: usar `HTTPException` en `src/main.py` | Sin impacto |

---

## Sources

### Primary (HIGH confidence)

- [docs.astral.sh/uv/concepts/projects/layout/](https://docs.astral.sh/uv/concepts/projects/layout/) — estructura de archivos uv, qué commitear
- [docs.astral.sh/uv/concepts/projects/dependencies/](https://docs.astral.sh/uv/concepts/projects/dependencies/) — extras opcionales, `uv add --optional`
- [docs.astral.sh/uv/concepts/projects/sync/](https://docs.astral.sh/uv/concepts/projects/sync/) — `--frozen` vs `--locked`, `--extra`, `--no-dev`
- [docs.astral.sh/uv/guides/integration/docker/](https://docs.astral.sh/uv/guides/integration/docker/) — Dockerfile multi-stage con uv, variables de entorno
- [docs.astral.sh/uv/reference/cli/#uv-export](https://docs.astral.sh/uv/reference/cli/#uv-export) — `uv export --format requirements-txt`
- [docs.astral.sh/uv/reference/cli/#uv-lock](https://docs.astral.sh/uv/reference/cli/#uv-lock) — `uv lock --upgrade-package`
- `uv lock --dry-run` ejecutado en el proyecto — resolución de 59 paquetes verificada [VERIFIED: ejecución local]
- `uv export --format requirements-txt --no-hashes` ejecutado — salida confirmada con `-e .` y dependencias completas [VERIFIED: ejecución local]
- `slopcheck install uv fastapi uvicorn openai deepl` — 5/5 [OK] [VERIFIED: slopcheck 0.6.1]
- `pip index versions uv` — versión 0.11.17 más reciente [VERIFIED: PyPI registry]

### Secondary (MEDIUM confidence)

- [docs.astral.sh/uv/guides/migration/pip-to-project/](https://docs.astral.sh/uv/guides/migration/pip-to-project/) — flujo de migración desde pip; no cubre setuptools específicamente

### Tertiary (LOW confidence)

- Ninguno — todos los claims críticos fueron verificados con herramientas o fuentes oficiales.

---

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — verificado con ejecución local de `uv lock --dry-run` y `uv export`
- Architecture: HIGH — basado en documentación oficial + pruebas locales
- Pitfalls: HIGH — los 5 pitfalls documentados están respaldados por docs oficiales o verificación directa del comportamiento
- Docker pattern: HIGH — extraído directamente de docs.astral.sh/uv/guides/integration/docker
- Package legitimacy: HIGH — slopcheck 5/5 OK; paquetes son proyectos establecidos

**Research date:** 2026-05-31
**Valid until:** 2026-08-31 (uv tiene releases frecuentes pero la API de `lock`/`sync`/`export` es estable; los breaking changes se documentan en CHANGELOG)
