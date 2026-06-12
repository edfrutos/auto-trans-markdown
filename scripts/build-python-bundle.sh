#!/usr/bin/env bash
# build-python-bundle.sh — descarga CPython standalone e instala dependencias del bundle macOS.
# Ejecutar una vez antes del primer build de Xcode y cada vez que cambie uv.lock:
#   ./scripts/build-python-bundle.sh
# Requiere: uv (https://astral.sh/uv), conexión a internet.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/python-bundle"

PBS_RELEASE="20260510"
PBS_VERSION="3.11.15"
PBS_ARCH="aarch64-apple-darwin"
PBS_FLAVOR="install_only_stripped"
PBS_ARTIFACT="cpython-${PBS_VERSION}+${PBS_RELEASE}-${PBS_ARCH}-${PBS_FLAVOR}.tar.gz"
PBS_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}/${PBS_ARTIFACT}"

echo "→ Descargando CPython ${PBS_VERSION} standalone (${PBS_RELEASE}, ${PBS_ARCH})..."
curl -L --progress-bar "$PBS_URL" -o /tmp/cpython-standalone.tar.gz

# Verificar estructura del tarball antes de extraer.
# El primer entry debe ser "python/" — si el formato cambia en futuras releases, el script falla aquí.
echo "→ Verificando estructura del tarball..."
FIRST_DIR=$(tar tzf /tmp/cpython-standalone.tar.gz 2>/dev/null | head -1)
if [[ "$FIRST_DIR" != "python/"* ]]; then
  echo "ERROR: estructura inesperada del tarball (primer entry: '$FIRST_DIR', esperado: prefijo 'python/')" >&2
  echo "       Puede que la release ${PBS_RELEASE} haya cambiado el layout. Revisa la URL:" >&2
  echo "       ${PBS_URL}" >&2
  exit 1
fi

echo "→ Extrayendo en ${BUNDLE_DIR}..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"
tar xzf /tmp/cpython-standalone.tar.gz -C "$BUNDLE_DIR" --strip-components=1

PYTHON="$BUNDLE_DIR/bin/python3"

# Exportar requirements desde uv.lock (sin dev, sin editable, sin hashes).
# Esto garantiza que el bundle usa exactamente las mismas versiones que el entorno de desarrollo.
echo "→ Exportando requirements desde uv.lock..."
cd "$REPO_ROOT"
uv export \
  --format requirements-txt \
  --no-dev \
  --no-editable \
  --no-emit-project \
  --no-hashes \
  > /tmp/bundle-requirements.txt

# Instalar dependencias en el site-packages del bundle Python embebido.
# Sin --target: uv resuelve el site-packages correcto desde el intérprete (lib/python3.11/site-packages/).
# PYTHONDONTWRITEBYTECODE: evita PermissionError al escribir .pyc en /Applications.
echo "→ Instalando dependencias en site-packages del bundle..."
PYTHONDONTWRITEBYTECODE=1 uv pip install \
  -r /tmp/bundle-requirements.txt \
  --python "$PYTHON"

# Smoke test: verificar que fastapi se puede importar desde el intérprete embebido.
echo "→ Smoke test: import fastapi..."
"$PYTHON" -c "import fastapi; print('OK — fastapi', fastapi.__version__)" || {
  echo "ERROR: el smoke test falló. El bundle no está correctamente instalado." >&2
  echo "       Intenta eliminar python-bundle/ y ejecutar el script de nuevo." >&2
  exit 1
}

rm -f /tmp/cpython-standalone.tar.gz /tmp/bundle-requirements.txt

# ---------------------------------------------------------------------------
# PERF-02: Reducir el tamaño del bundle eliminando archivos innecesarios
# en runtime. Objetivo: de ~200 MB → < 120 MB.
# ---------------------------------------------------------------------------
BEFORE_SIZE=$(du -sh "$BUNDLE_DIR" | cut -f1)
echo "→ Tamaño antes de la limpieza: ${BEFORE_SIZE}"
echo "→ Eliminando archivos innecesarios del bundle..."

PYLIB="$BUNDLE_DIR/lib/python3.11"
SITE="$PYLIB/site-packages"

# 1. Suite de tests de CPython (~52 MB) — nunca se ejecuta en la app.
rm -rf "$PYLIB/test" 2>/dev/null || true

# 2. IDLE — IDE de Python, no necesario (~5 MB).
rm -rf "$PYLIB/idlelib" 2>/dev/null || true

# 3. Tkinter + turtle (~4 MB) — UI toolkit no usado por el backend FastAPI.
rm -rf "$PYLIB/tkinter" 2>/dev/null || true
rm -f  "$PYLIB/turtle.py" "$PYLIB/turtledemo" 2>/dev/null || true

# 4. ensurepip (~2 MB) — bootstrapper pip, no necesario en runtime.
rm -rf "$PYLIB/ensurepip" 2>/dev/null || true

# 5. lib2to3 (~1 MB) — herramienta de migración Python 2→3, no necesaria.
rm -rf "$PYLIB/lib2to3" 2>/dev/null || true

# 6. Directorios de tests dentro de site-packages (~5 MB agregados).
find "$SITE" -maxdepth 2 -type d \( -name "test" -o -name "tests" -o -name "testing" \) \
  -exec rm -rf {} + 2>/dev/null || true

# 7. Metadatos pip (.dist-info) en site-packages (~8 MB) — solo útiles para
#    `pip show/list`; no se necesitan para importar paquetes en runtime.
find "$SITE" -maxdepth 1 -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true

# 8. Type stubs (.pyi) — solo útiles para IDEs y type checkers (~2 MB).
find "$BUNDLE_DIR/lib" -name "*.pyi" -delete 2>/dev/null || true

# 9. Headers C (~5 MB) — solo necesarios para compilar extensiones C desde source.
rm -rf "$BUNDLE_DIR/include" 2>/dev/null || true

# 10. share/ — man pages y datos auxiliares no necesarios en runtime (~1 MB).
rm -rf "$BUNDLE_DIR/share" 2>/dev/null || true

# 11. Archivos __pycache__ huérfanos en stdlib (quedan tras eliminar test/idlelib/etc).
find "$PYLIB" -maxdepth 2 -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# ---------------------------------------------------------------------------
# PERF-03: Pre-compilar todos los .py → .pyc para reducir el tiempo de
# importación en el primer arranque en frío.
# PYTHONDONTWRITEBYTECODE=1 en ServerManager impide que Python intente
# re-escribir .pyc en /Applications (sin permisos), pero los .pyc ya presentes
# en el bundle se usan directamente sin recompilación.
# ---------------------------------------------------------------------------
echo "→ Pre-compilando .py → .pyc (startup más rápido)..."
"$PYTHON" -m compileall -q -j0 "$PYLIB" 2>/dev/null || true

AFTER_SIZE=$(du -sh "$BUNDLE_DIR" | cut -f1)
echo "→ Tamaño tras la limpieza:    ${AFTER_SIZE}"

echo ""
echo "✓ python-bundle listo en ${BUNDLE_DIR}"
echo "  Intérprete: ${PYTHON}"
echo "  Tamaño: ${BEFORE_SIZE} → ${AFTER_SIZE}"
echo "  Siguiente paso: abre Xcode y compila el target MDTranslator (Cmd+B)."
