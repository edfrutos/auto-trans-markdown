# Performance — MD Translator macOS App

## Objetivos v3.1

| Métrica | Baseline v3.0 | Objetivo v3.1 | Estado |
|---------|--------------|---------------|--------|
| Arranque en frío (doble clic → UI lista) | ~8–10 s | < 5 s | 🔄 en progreso |
| Tamaño `python-bundle/` | ~200 MB | < 120 MB | 🔄 en progreso |
| RSS en reposo (app sin traducir) | ~180 MB | < 200 MB | ✅ dentro de objetivo |
| Tiempo respuesta `/api/translate` (texto corto) | ~2–4 s | < 4 s | ✅ dentro de objetivo |

---

## Cómo medir

### Arranque en frío

Medición manual (3 ejecuciones, mediana):

```bash
# 1. Cerrar la app si está abierta
# 2. Purgar la caché de archivos del SO
sudo purge

# 3. Medir con time (aproximado; el log del servidor da el timestamp exacto)
time open -n ~/Applications/MDTranslator.app

# 4. Leer el log para timestamps precisos
tail -f /tmp/md-translator-server.log
```

El timestamp de arranque real se puede extraer del log del servidor:

```bash
# Primer "Application startup complete" de uvicorn
grep "Application startup complete" /tmp/md-translator-server.log | head -1
```

Para medición precisa con Instruments:

1. Xcode → Product → Profile (⌘I)
2. Template: **Time Profiler**
3. Instrument adicional: **Allocations**
4. Arrancar la app desde Instruments
5. Medir el intervalo desde `MDTranslatorApp.init()` hasta `state == .running` en ServerManager

### Tamaño del bundle

```bash
# Tamaño total del python-bundle/
du -sh python-bundle/

# Desglose por directorio
du -sh python-bundle/lib/python3.11/*/  | sort -rh | head -20
du -sh python-bundle/lib/python3.11/site-packages/*/ | sort -rh | head -20
```

### RSS en reposo

```bash
# PID del proceso principal Swift
pgrep MDTranslator
# Memoria RSS (en KB)
ps -o rss= -p $(pgrep MDTranslator)
# O con Activity Monitor → columna "Memoria real"
```

---

## Mediciones base v3.0 (2026-06-09)

> Mediciones realizadas en Mac Studio M2 (16 GB RAM, macOS 14.5).
> Bundle generado con `build-python-bundle.sh` sin optimizaciones de limpieza.

| Métrica | Valor medido | Notas |
|---------|-------------|-------|
| Arranque en frío (1ª ejecución) | ~9.2 s | Python importa sin `.pyc` precalculados |
| Arranque en caliente (2ª ejecución) | ~6.8 s | `.pyc` en caché del SO |
| `python-bundle/` total | ~197 MB | Incluye stdlib test/, idlelib, tkinter |
| — stdlib `test/` | ~52 MB | Suite de tests de CPython, no necesaria |
| — `idlelib/` | ~4.8 MB | IDE de Python, no necesario |
| — `tkinter/` | ~3.1 MB | Binding Tk, no necesario |
| — `ensurepip/` | ~2.2 MB | Bootstrapper pip, no necesario |
| — `site-packages/*.dist-info/` | ~8 MB | Metadatos pip, no necesarios en runtime |
| — `.pyi` stubs | ~1.5 MB | Hints para IDEs, no necesarios en runtime |
| RSS en reposo | ~185 MB | Python + FastAPI cargados |
| `/api/translate` texto corto | ~2.1 s | gpt-4o-mini, segmento único |

---

## Optimizaciones implementadas (v3.1 Phase 15)

### PERF-02 — Limpieza del bundle (build-python-bundle.sh)

Directorios y archivos eliminados tras `uv pip install`:

| Objetivo | Ahorro estimado |
|----------|----------------|
| `lib/python3.11/test/` | ~52 MB |
| `lib/python3.11/idlelib/` | ~5 MB |
| `lib/python3.11/tkinter/` + `turtle*` | ~4 MB |
| `lib/python3.11/ensurepip/` | ~2 MB |
| `lib/python3.11/site-packages/*.dist-info/` | ~8 MB |
| `.pyi` stubs en site-packages | ~2 MB |
| `include/` headers C | ~5 MB |
| `share/` (man pages, etc.) | ~1 MB |
| `__pycache__` → sustituidos por `.pyc` vía `compileall` | ~5 MB neto |
| **Total estimado** | **~80 MB** → bundle ~120 MB |

Además, `python -m compileall` pre-compila todos los `.py` a `.pyc` para reducir
el tiempo de importación en el primer arranque.

### PERF-03 — Polling del health check (ServerManager.swift)

- Intervalo de polling reducido de 500 ms → 200 ms
- Argumento uvicorn `--log-level warning` añadido (menos I/O en startup)
- Ahorro estimado: 0.3–0.6 s en el arranque (1–2 reintentos menos hasta health check OK)

---

## Mediciones objetivo post-v3.1

> Actualizar esta tabla tras ejecutar `make smoke-test` en el hardware de referencia.

| Métrica | Objetivo | Medido | Fecha |
|---------|----------|--------|-------|
| Arranque en frío | < 5 s | — | — |
| `python-bundle/` | < 120 MB | — | — |
| RSS en reposo | < 200 MB | — | — |

---

## TEST-01 — Smoke test automatizado

El smoke test lanza el servidor en el puerto 15499, verifica el health check y ejerce el
pipeline de estimación de coste (parser + estimador). No requiere API key real.

```bash
# Activar el entorno virtual y ejecutar el test
source .venv/bin/activate
make smoke-test
```

Salida esperada:

```
-> smoke-test Phase 15 — TEST-01
   python: .venv/bin/python | puerto: 15499 | log: /tmp/md-translate-smoke.log
-> Arrancando servidor Python...
-> Health check /api/languages (máx 15 s, poll 500 ms)...
   PASS  GET /api/languages  → 200
-> POST /api/translate/estimate (no requiere API key real)...
   PASS  POST /api/translate/estimate  → 200
   {"segments": 2, "characters": 47, "estimated_cost_usd": 0.000047, ...}

smoke-test OK
```

Si no hay API key configurada, `/api/translate/estimate` devuelve 503 y el test lo muestra
como `SKIP` (no es un fallo).

---

## Referencias

- [python-build-standalone releases](https://github.com/astral-sh/python-build-standalone/releases)
- [uvicorn CLI reference](https://www.uvicorn.org/settings/)
- [Instruments Time Profiler — Apple Developer](https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use)
