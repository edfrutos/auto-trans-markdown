---
phase: 9
slug: python-embedding-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-03
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property               | Value                                                                   |
| ---------------------- | ----------------------------------------------------------------------- |
| **Framework**          | pytest 8.0+ (configurado en `pyproject.toml [tool.pytest.ini_options]`) |
| **Config file**        | `pyproject.toml` (`[tool.pytest.ini_options]`)                          |
| **Quick run command**  | `pytest tests/ -q -x`                                                   |
| **Full suite command** | `pytest tests/ -v`                                                      |
| **Estimated runtime**  | ~10 seconds (148 tests existentes — sin cambios en código Python)       |

**Nota:** Phase 9 añade código Swift y un script bash, no código Python nuevo. Los 148 tests pytest existentes deben pasar sin modificación. Las verificaciones de BUNDLE-03/04/05 son manuales (requieren Xcode + app en ejecución).

---

## Sampling Rate

- **After every task commit:** Run `pytest tests/ -q -x`
- **After every plan wave:** Run `pytest tests/ -v` + `./scripts/build-python-bundle.sh` (si el script fue modificado en esa wave)
- **Before `/gsd:verify-work`:** Suite Python verde + smoke test del bundle verde + verificaciones manuales de BUNDLE-03/04/05
- **Max feedback latency:** ~10 seconds (pytest) / ~3 min (build script completo)

---

## Per-Task Verification Map

| Task ID   | Plan   | Wave   | Requirement   | Threat Ref   | Secure Behavior                                   | Test Type   | Automated Command                                                                 | File Exists   | Status    |
| --------- | ------ | ------ | ------------- | ------------ | ------------------------------------------------- | ----------- | --------------------------------------------------------------------------------- | ------------- | --------- |
| 09-01-01  | 01     | 1      | BUNDLE-01     | T-09-01      | Tarball descargado de GitHub Releases (no espejo) | script      | `./scripts/build-python-bundle.sh && test -f python-bundle/bin/python3`           | ❌ W0          | ⬜ pending |
| 09-01-02  | 01     | 1      | BUNDLE-02     | —            | N/A                                               | script      | `python-bundle/bin/python3 -c "import fastapi; print('OK')"`                      | ❌ W0          | ⬜ pending |
| 09-01-03  | 01     | 1      | BUNDLE-01     | —            | N/A                                               | manual      | Verificar `python-bundle/bin/python3 --version` retorna `Python 3.11.15`          | ❌ W0          | ⬜ pending |
| 09-02-01  | 02     | 1      | BUNDLE-03     | —            | N/A                                               | manual      | Xcode build pasa sin errores; proceso uvicorn en Activity Monitor con puerto != 0 | ❌ W0          | ⬜ pending |
| 09-02-02  | 02     | 1      | BUNDLE-04     | T-09-02      | Servidor bound a 127.0.0.1 exclusivamente         | manual      | `GET http://127.0.0.1:PORT/api/languages` responde 200 en < 15s tras lanzar app   | ❌ W0          | ⬜ pending |
| 09-02-03  | 02     | 1      | BUNDLE-05     | T-09-03      | Proceso Python termina al cerrar app              | manual      | Proceso uvicorn desaparece de Activity Monitor en < 5s tras Cmd+Q                 | ❌ W0          | ⬜ pending |
| 09-03-01  | 03     | 1      | —             | —            | N/A                                               | unit        | `pytest tests/ -q -x` (regresión Python)                                          | ✅ existe      | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/build-python-bundle.sh` — script principal de Phase 9 (BUNDLE-01, BUNDLE-02); no existe aún en el repo
- [ ] `macos/MDTranslator.xcodeproj/project.pbxproj` — proyecto Xcode (BUNDLE-03, BUNDLE-04, BUNDLE-05); directorio `macos/` no existe aún
- [ ] `.gitignore` — añadir entrada `python-bundle/` (actualmente no está en .gitignore)

*Los tests pytest existentes (148 tests) cubren todo el código Python existente — no hay Wave 0 gaps en la suite pytest.*

---

## Manual-Only Verifications

| Behavior                                                                  | Requirement             | Why Manual                                                                          | Test Instructions                                                                                                                                                                                                             |
| ------------------------------------------------------------------------- | ----------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Puerto libre asignado por kernel y subprocess visible en Activity Monitor | BUNDLE-03               | Requiere app Xcode en ejecución; no hay API automática para leer pid del subprocess | 1. Compilar y lanzar app desde Xcode. 2. Abrir Activity Monitor. 3. Verificar proceso `python3` como child de `MD Translator`. 4. Verificar puerto con `lsof -p PID` y filtrar LISTEN                                         |
| Health check `GET /api/languages` responde en < 15s                       | BUNDLE-04               | Requiere verificación visual de la splash y comportamiento temporal                 | 1. Lanzar app. 2. Verificar que SplashView aparece con ProgressView. 3. Verificar que desaparece y la vista principal carga en < 15s. 4. Opcionalmente: `curl http://127.0.0.1:PORT/api/languages`                            |
| Proceso Python desaparece en < 5s tras cerrar app                         | BUNDLE-05               | Requiere monitoreo visual en Activity Monitor                                       | 1. Lanzar app y confirmar que funciona. 2. Abrir Activity Monitor con filtro `python3`. 3. Cerrar app con Cmd+Q. 4. Verificar que el proceso desaparece en < 5s                                                               |
| SplashView visible durante arranque, desaparece al pasar health check     | SC-5 (success criteria) | Verificación visual de UI                                                           | 1. Lanzar app. 2. Verificar ProgressView visible. 3. Verificar que al pasar el health check la splash desaparece. 4. Repetir con `kill -STOP PID` del proceso Python para simular arranque lento                              |
| `.alert()` con Reintentar/Salir aparece si health check falla             | D-05                    | Requiere simular fallo del servidor                                                 | 1. Modificar temporalmente el timeout a 1s o matar el proceso Python durante arranque. 2. Verificar que el alert aparece con ambos botones. 3. Verificar "Reintentar" relanza el proceso. 4. Verificar "Salir" cierra la app. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (build script, Xcode project, .gitignore)
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s (pytest) / < 3min (build script)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
