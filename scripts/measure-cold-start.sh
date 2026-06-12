#!/usr/bin/env bash
# measure-cold-start.sh — PERF-03 (REL-05): mide el arranque en frío de MDTranslator.app
#
# Mide desde `open` hasta que GET /api/languages responde 200 (servidor listo).
# El puerto es dinámico: se obtiene del PID del subprocess Python
# (/tmp/md-translator-python.pid, escrito por ServerManager al lanzar).
#
# Uso: ./scripts/measure-cold-start.sh [n_runs]   (por defecto 3; se reporta la mediana)

set -euo pipefail

APP="/Applications/MDTranslator.app"
PIDFILE="/tmp/md-translator-python.pid"
RUNS="${1:-3}"

if [ ! -d "$APP" ]; then
  echo "ERROR: $APP no existe. Instala la app primero."
  exit 1
fi

results=()

for i in $(seq 1 "$RUNS"); do
  osascript -e 'quit app "MDTranslator"' >/dev/null 2>&1 || true
  sleep 3
  rm -f "$PIDFILE"

  START=$(python3 -c 'import time; print(time.time())')
  open "$APP"

  # 1) Esperar a que ServerManager escriba el PID del subprocess (máx 30 s)
  PID=""
  for _ in $(seq 1 600); do
    if [ -f "$PIDFILE" ]; then
      PID=$(cat "$PIDFILE" 2>/dev/null || true)
      [ -n "$PID" ] && break
    fi
    sleep 0.05
  done
  if [ -z "$PID" ]; then
    echo "ERROR: no apareció $PIDFILE en 30 s. ¿Arrancó la app?"
    exit 1
  fi

  # 2) Obtener el puerto en escucha de ese PID (máx 30 s)
  PORT=""
  for _ in $(seq 1 600); do
    PORT=$(lsof -nP -iTCP -sTCP:LISTEN -a -p "$PID" 2>/dev/null | awk 'NR>1 {sub(/.*:/,"",$9); print $9; exit}') || true
    [ -n "$PORT" ] && break
    sleep 0.05
  done
  if [ -z "$PORT" ]; then
    echo "ERROR: el PID $PID no tiene puerto en escucha."
    exit 1
  fi

  # 3) Health check — el mismo criterio que usa la app para mostrar la UI
  until curl -sf -o /dev/null "http://127.0.0.1:${PORT}/api/languages"; do
    sleep 0.05
  done

  END=$(python3 -c 'import time; print(time.time())')
  T=$(python3 -c "print(f'{${END} - ${START}:.2f}')")
  results+=("$T")
  echo "Run ${i}: ${T}s (puerto ${PORT}, pid ${PID})"
done

echo ""
printf '%s\n' "${results[@]}" | sort -n | awk '
  {a[NR]=$1}
  END {
    m = (NR % 2) ? a[(NR+1)/2] : (a[NR/2] + a[NR/2+1]) / 2
    printf "Mediana arranque en frío: %.2fs (%d runs)\n", m, NR
  }'
echo "Anota la mediana en docs/performance.md → tabla \"Mediciones objetivo post-v3.1\" (objetivo < 5 s)."
