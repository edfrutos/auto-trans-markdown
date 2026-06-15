---
phase: 09-python-embedding-foundation
plan: 01
status: completed
completed: "2026-06-07"
requirements_delivered:

  - BUNDLE-01
  - BUNDLE-02

---

# Plan 09-01 Summary — Python Bundle Build Script

## What Was Built

### `scripts/build-python-bundle.sh` (nuevo)
Script bash ejecutable que:

1. Descarga CPython 3.11.15 standalone (python-build-standalone, release 20260510, `aarch64-apple-darwin`, `install_only_stripped`) desde GitHub Releases
2. Verifica la estructura del tarball antes de extraer (primer entry debe ser `python/`) — mitiga Pitfall 1
3. Extrae en `python-bundle/` con `--strip-components=1`
4. Exporta requirements desde `uv.lock` con `uv export --format requirements-txt --no-dev --no-editable --no-emit-project --no-hashes`
5. Instala las dependencias en `python-bundle/lib/python3.11.15/site-packages/` con `uv pip install`
6. Smoke test: `import fastapi` — exit 1 si falla
7. Limpia archivos temporales `/tmp/cpython-standalone.tar.gz` y `/tmp/bundle-requirements.txt`
8. `PYTHONDONTWRITEBYTECODE=1` inyectado al instalar — mitiga Pitfall 2 (PermissionError en /Applications)

### `.gitignore` (modificado)
Añadida sección `# --- macOS app bundle (generado por build-python-bundle.sh) ---` con:

- `python-bundle/`
- `macos/MDTranslator/MDTranslator.xcodeproj/xcuserdata/`
- `macos/MDTranslator/MDTranslator.xcodeproj/project.xcworkspace/xcuserdata/`
- `*.xcuserstate`

### `README.md` (modificado)
Añadida sección `## App nativa macOS — Prerequisito` antes de `## Uso` con:

- Instrucción de instalar `uv` (con comando curl)
- Instrucción de ejecutar `./scripts/build-python-bundle.sh`
- Mención de que `python-bundle/` está en `.gitignore` y no se versiona
- Cuándo re-ejecutar (cuando cambie `uv.lock`)

## Verification

Todos los acceptance criteria del plan superados:

- ✅ `scripts/build-python-bundle.sh` existe y es ejecutable (`test -x`)
- ✅ Contiene `install_only_stripped` (flavor correcto)
- ✅ Contiene `20260510` (release correcto)
- ✅ Contiene `aarch64-apple-darwin` (arquitectura correcta)
- ✅ Contiene `--strip-components=1` (mitigación Pitfall 1)
- ✅ Contiene verificación de estructura del tarball (`tar tzf | head -1` con check de `python/`)
- ✅ Contiene `uv export` y `uv pip install` (pipeline uv, D-03)
- ✅ Contiene smoke test `import fastapi` con `exit 1` en fallo
- ✅ Contiene `PYTHONDONTWRITEBYTECODE` (mitigación Pitfall 2)
- ✅ `bash -n scripts/build-python-bundle.sh` → exit 0 (sintaxis válida)
- ✅ `.gitignore` contiene `python-bundle/` y artefactos Xcode de usuario
- ✅ `README.md` documenta el prerequisito con referencia al script y a `uv.lock`
- ⚠️ `pytest tests/ -q -x` — no ejecutable en sandbox Linux (`.venv` apunta a Python 3.14 macOS); ningún fichero Python modificado → sin riesgo de regresión

## Notes

- El script asume Apple Silicon (`aarch64-apple-darwin`). Para Intel habría que cambiar `PBS_ARCH` a `x86_64-apple-darwin` — diferido a v3.1 (Universal Binary out of scope v3.0).
- La ruta del `.gitignore` refleja la ubicación real del proyecto Xcode en el repo (`macos/MDTranslator/MDTranslator.xcodeproj`), que difiere de la ruta especificada en el plan original (`macos/MDTranslator.xcodeproj`). Pendiente de corrección en Plan 09-02.
