# Phase 9: Python Embedding Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 09-python-embedding-foundation
**Areas discussed:** Dev workflow, UI de arranque, Scaffold Swift (Phase 9 vs 10), Estructura del bundle

---

## Dev Workflow

| Option                                 | Description                                                                                                | Selected   |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------- | ---------- |
| Manual — una vez, antes de abrir Xcode | Bundle se genera una vez, reutilizado en sucesivas compilaciones. Requiere re-ejecutar al actualizar deps. | ✓          |
| Xcode Run Script build phase           | Se ejecuta automáticamente cada build. Añade ~2-3 min a cada build limpio.                                 |            |
| Makefile target (make bundle)          | make bundle como prerequisito de make build. Flujo clásico con xcodebuild.                                 |            |

**User's choice:** Manual — una vez, antes de abrir Xcode

| Option                            | Description                                                                      | Selected   |
| --------------------------------- | -------------------------------------------------------------------------------- | ---------- |
| .gitignore — regenerar localmente | Bundle ~100-200 MB, demasiado grande para git. README documenta el prerequisito. | ✓          |
| Git LFS para el bundle            | Permite versionar el bundle pero requiere git-lfs en todos los dev.              |            |

**User's choice:** .gitignore — regenerar localmente

| Option                                        | Description                                                                  | Selected   |
| --------------------------------------------- | ---------------------------------------------------------------------------- | ---------- |
| python-bundle/ en raíz del repo (gitignored)  | Ruta predecible: python-bundle/bin/python3. Xcode lo copia al .app en build. | ✓          |
| macos/PythonBundle/ dentro del proyecto Xcode | Más integrado pero mezcla artifacts con fuentes Swift.                       |            |

**User's choice:** python-bundle/ en la raíz del repo (gitignored)

| Option                  | Description                                                                  | Selected   |
| ----------------------- | ---------------------------------------------------------------------------- | ---------- |
| uv pip install --target | uv package manager, instala desde uv.lock. Absorbe requisitos lockfile v2.1. | ✓          |
| pip install --target    | Más familiar. Sin lockfile por defecto.                                      |            |

**User's choice:** uv pip install --target

---

## UI de Arranque

| Option                                                | Description                                                                               | Selected   |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------- | ---------- |
| Ventana splash minimalista con ProgressView spinner   | Ventana SwiftUI pequeña, sin título, ProgressView girando + "Iniciando...". Nativa macOS. | ✓          |
| NSAlert o sheet de carga sin ventana propia           | Sheet sobre ventana principal (problemático — ventana principal no existe en Phase 9).    |            |
| Ventana splash con barra de progreso y fases de texto | Progreso textual detallado. Más informativo pero más código para Phase 9.                 |            |

**User's choice:** Ventana splash minimalista con ProgressView spinner

| Option                                      | Description                                                | Selected   |
| ------------------------------------------- | ---------------------------------------------------------- | ---------- |
| Alert nativo con botones Reintentar / Salir | NSAlert/.alert() con mensaje de error claro, dos opciones. | ✓          |
| Cerrar la app automáticamente               | Silencioso, mal para depuración.                           |            |
| Mostrar log de error inline en la splash    | Más información pero complica la UI de Phase 9.            |            |

**User's choice:** Alert nativo con botones Reintentar / Salir

| Option                                     | Description                                                          | Selected   |
| ------------------------------------------ | -------------------------------------------------------------------- | ---------- |
| Claude decide — coherente con macOS nativo | Ventana sin barra de título, redondeada, nombre de la app y spinner. | ✓          |
| Quiero especificar el diseño               | Usuario especifica tamaño, colores, contenido exacto.                |            |

**User's choice:** Claude decide — coherente con macOS nativo

---

## Scaffold Swift (Phase 9 vs 10)

| Option                                                    | Description                                                                                                 | Selected   |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ---------- |
| Solo fundamentos: App struct + ServerManager + SplashView | @main App struct, ServerManager, SplashView como WindowGroup principal. Phase 10 añade NavigationSplitView. | ✓          |
| Ya crear NavigationSplitView con sidebar vacío            | Empieza con estructura de Phase 10 pero sin contenido. Más acoplado entre fases.                            |            |

**User's choice:** Solo los fundamentos: App struct + ServerManager + SplashView

| Option                       | Description                                                                                   | Selected   |
| ---------------------------- | --------------------------------------------------------------------------------------------- | ---------- |
| .xcodeproj tradicional       | Flexible para Sparkle SPM, targets de test, scripts de build phase. Estándar para apps macOS. | ✓          |
| Package.swift (SwiftPM puro) | Más ligero pero app bundles/entitlements son más complejos sin Xcode.                         |            |

**User's choice:** .xcodeproj tradicional

| Option                   | Description                                     | Selected   |
| ------------------------ | ----------------------------------------------- | ---------- |
| MD Translator            | Nombre corto. Aparece en barra de menús y Dock. | ✓          |
| Markdown Auto Translator | Nombre completo del proyecto.                   |            |
| AutoTrans                | Nombre corto alternativo.                       |            |

**User's choice:** MD Translator

| Option                      | Description                                                      | Selected   |
| --------------------------- | ---------------------------------------------------------------- | ---------- |
| com.edefrutos.md-translator | Derivado del email del desarrollador. Estándar para apps ad-hoc. | ✓          |
| com.auto-trans-markdown.app | Derivado del nombre del repo.                                    |            |

**User's choice:** com.edefrutos.md-translator

---

## Estructura del Bundle

| Option                      | Description                                                                  | Selected   |
| --------------------------- | ---------------------------------------------------------------------------- | ---------- |
| Contents/Resources/python/  | Ruta estándar para recursos no ejecutables. Bundle.main.resourceURL/python/. | ✓          |
| Contents/Frameworks/python/ | Para bibliotecas compartidas. Poco adecuado para un intérprete completo.     |            |
| Contents/MacOS/python/      | Funciona pero mezcla ejecutable Swift con bundle Python.                     |            |

**User's choice:** Contents/Resources/python/

| Option                             | Description                                                                    | Selected   |
| ---------------------------------- | ------------------------------------------------------------------------------ | ---------- |
| Contents/Resources/backend/        | Agrupa todo el backend. Swift lanza uvicorn desde Resources/backend/ como CWD. | ✓          |
| Contents/Resources/ (directamente) | src/, tests/ y pyproject.toml sueltos en Resources/. Más difícil de separar.   |            |

**User's choice:** Contents/Resources/backend/

| Option                                                                | Description                                                      | Selected   |
| --------------------------------------------------------------------- | ---------------------------------------------------------------- | ---------- |
| Dentro del intérprete: Resources/python/lib/python3.11/site-packages/ | Auto-contenido en python/. Sin PYTHONPATH extra.                 | ✓          |
| Carpeta separada Resources/backend/site-packages/                     | Requiere PYTHONPATH al arrancar. Más complejo sin ventaja clara. |            |

**User's choice:** Dentro del intérprete: Resources/python/lib/python3.11/site-packages/

---

## Claude's Discretion

- Tamaño exacto y padding de la ventana splash
- Nombre del actor Swift para gestión del servidor (ServerManager, PythonServerManager, etc.)
- Patrón exacto de discover-port (bind socket a 0 → leer puerto → cerrar → pasar --port N a uvicorn)

## Deferred Ideas

- NavigationSplitView completo con sidebar → Phase 10
- Gestión de API keys (Keychain, SecureField en Settings) → Phase 10
- Notificaciones de batch, glosario, TM → Phase 11
- Firma ad-hoc de .dylib/.so del bundle → Phase 12 (make dmg)
- Universal Binary (arm64+x86_64) → v3.1
- SSE streaming de progreso → v3.1
