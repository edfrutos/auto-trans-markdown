---
phase: 8
slug: reproducible-dependencies
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-31
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property               | Value                                              |
| ---------------------- | -------------------------------------------------- |
| **Framework**          | pytest (en `[project.optional-dependencies] test`) |
| **Config file**        | `pyproject.toml` → `[tool.pytest.ini_options]`     |
| **Quick run command**  | `uv sync --extra test && pytest tests/ -q`         |
| **Full suite command** | `pytest tests/ -v`                                 |
| **Estimated runtime**  | ~30 seconds                                        |

---

## Sampling Rate

- **After every task commit:** `test -f uv.lock && uv sync && python -c "import fastapi"`
- **After each wave:** `pytest tests/ -q` + smoke Docker
- **Phase gate:** todos los checks de la tabla de requirements en verde

---

## Requirements → Test Map

| Req ID   | Behavior                                                   | Test Type   | Automated Command                                                                                     |
| -------- | ---------------------------------------------------------- | ----------- | ----------------------------------------------------------------------------------------------------- |
| LOCK-01  | `uv.lock` existe y está commiteado                         | smoke       | `test -f uv.lock && git ls-files uv.lock`                                                             |
| LOCK-02  | `uv sync` crea `.venv` funcional                           | integration | `uv sync && python -c "import fastapi; import openai"`                                                |
| LOCK-03  | `uv add` / `uv lock --upgrade-package` actualizan lockfile | manual      | — (requiere red y modificar deps reales)                                                              |
| LOCK-04  | README contiene bloques uv y pip                           | smoke       | `grep -q "uv sync" README.md && grep -q "pip install" README.md`                                      |
| LOCK-05  | Docker build funcional con `uv sync --frozen`              | integration | `docker build -t md-translate-test . && docker run --rm md-translate-test python -c "import fastapi"` |

---

## Nyquist Compliance

`nyquist_compliant: true` — los elementos `<automated>` en los `<verify>` de cada tarea son sustitutos equivalentes a ficheros de test pytest para esta fase, por las siguientes razones:

- **LOCK-01, LOCK-04:** Son comprobaciones de artefactos de sistema de ficheros y contenido de texto (existencia de fichero, grep en README). No hay lógica de negocio testable con pytest; los comandos shell en `<verify>` son la forma canónica de verificar este tipo de invariantes.
- **LOCK-02:** `uv sync --dry-run` en el `<verify>` de la Tarea 2 del Plan 01 verifica que el lockfile es coherente y que el entorno se puede reproducir. La validación de importabilidad (`python -c "import fastapi; import openai"`) completa la cobertura funcional. Escribir un test pytest que haga lo mismo solo duplicaría el shell check sin añadir valor.
- **LOCK-03:** Requiere modificar dependencias reales y acceso a red; por diseño es manual. No existe sustituto automatizable sin efectos secundarios en el entorno de CI.
- **LOCK-05:** Requiere el runtime de Docker. No es ejecutable dentro de un proceso pytest estándar. El `<verify>` de la Tarea 1 del Plan 02 incluye comprobaciones grep del Dockerfile y docker-compose.yml; el `docker build` y `docker run` de la sección `<verification>` constituyen la prueba de integración completa.

Wave 0 no genera ficheros `test_*.py` porque ningún requisito de esta fase contiene lógica de negocio pura (transformaciones de datos, algoritmos) susceptible de TDD con contratos entrada/salida predecibles.
