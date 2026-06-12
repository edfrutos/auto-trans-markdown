# Plan 09-02 — SUMMARY
## Corregir scaffold Xcode (acciones manuales)

**Estado:** COMPLETADO  
**Fecha:** 2026-06-07 / 2026-06-08

---

## Qué se hizo

### Correcciones en Xcode (manual)

| Ajuste | Valor configurado |
|--------|------------------|
| Deployment Target | macOS 14.0 |
| Bundle Identifier | `com.edefrutos.md-translator` |
| Signing Certificate | Sign to Run Locally |
| User Script Sandboxing | No (Build Settings) |
| App Sandbox capability | Eliminado (Signing & Capabilities) |

### Run Script phase añadida

Fase "Copy Python Bundle & Backend" en Build Phases:

```bash
#!/bin/bash
set -euo pipefail
REPO_ROOT="${SRCROOT}/../.."
RESOURCES="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources"
if [ -d "${REPO_ROOT}/python-bundle" ]; then
  rsync -a --delete "${REPO_ROOT}/python-bundle/" "${RESOURCES}/python/"
else
  echo "warning: python-bundle no encontrado. Ejecuta scripts/build-python-bundle.sh primero."
fi
rsync -a --delete "${REPO_ROOT}/src/" "${RESOURCES}/backend/src/"
cp "${REPO_ROOT}/pyproject.toml" "${RESOURCES}/backend/"
cp "${REPO_ROOT}/uv.lock" "${RESOURCES}/backend/"
```

**Checkbox "Based on dependency analysis" desactivado** — sin esta opción Xcode omitía el script en builds incrementales.

---

## Problemas encontrados y soluciones

| Problema | Causa | Solución |
|----------|-------|----------|
| rsync denegado | User Script Sandboxing activo | Build Settings → User Script Sandboxing → No |
| Run Script omitido en rebuild | "Based on dependency analysis" sin inputs/outputs | Desmarcar ese checkbox |
| `p.run()` falla silenciosamente | App Sandbox bloquea ejecución de subprocesos | Eliminar capability App Sandbox en Signing & Capabilities |

---

## Estado de artefactos

- `macos/MDTranslator/MDTranslator.xcodeproj` — configuración corregida
- Run Script phase operativa: copia `python-bundle/` y `src/` a `Resources/`
- App Sandbox eliminado (necesario para subprocess Python)
