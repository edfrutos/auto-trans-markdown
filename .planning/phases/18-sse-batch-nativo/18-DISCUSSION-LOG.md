# Phase 18: SSE Batch Nativo - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-12
**Phase:** 18-SSE Batch Nativo
**Areas discussed:** UI de progreso, Destino de resultados, Cancelación, Entrada del lote

---

## UI de progreso

| Option                         | Description                                                                              | Selected   |
| ------------------------------ | ---------------------------------------------------------------------------------------- | ---------- |
| Sheet en ventana principal     | Hoja SwiftUI anclada a la ventana principal; patrón macOS estándar; fácil con `.sheet()` | ✓          |
| Panel flotante independiente   | NSPanel auxiliar que flota mientras se usa el editor; más código                         |            |
| Popover desde la barra de menú | Reutilizar MenuBarView; progreso de segmentos quedaría apretado                          |            |

**User's choice:** Sheet en ventana principal

| Option                                | Description                                                                           | Selected   |
| ------------------------------------- | ------------------------------------------------------------------------------------- | ---------- |
| Barra global + archivo en curso       | Barra determinada (hechos/total) + archivo en curso con barra de segmentos + contador | ✓          |
| Lista completa de archivos con estado | Tabla con estado individual por archivo; más UI                                       |            |
| Minimalista: solo barra global        | No cumple del todo SSE-02                                                             |            |

**User's choice:** Barra global + archivo en curso

| Option                            | Description                                                                | Selected   |
| --------------------------------- | -------------------------------------------------------------------------- | ---------- |
| Resumen y cierre manual           | Resumen (N traducidos, M errores) + botones "Cerrar" y "Mostrar en Finder" | ✓          |
| Autocierre + notificación         | La sheet se cierra sola; errores en alert separado                         |            |
| Autocierre solo si no hay errores | Híbrido                                                                    |            |

**User's choice:** Resumen y cierre manual

| Option                       | Description                                                      | Selected   |
| ---------------------------- | ---------------------------------------------------------------- | ---------- |
| Sí, botón "En segundo plano" | El job sigue, el Dock muestra progreso, notificación al terminar | ✓          |
| No, modal hasta el final     | Más simple, menos flexible                                       |            |

**User's choice:** Sí, botón "Continuar en segundo plano"

---

## Destino de resultados

| Option                           | Description                                                                              | Selected   |
| -------------------------------- | ---------------------------------------------------------------------------------------- | ---------- |
| Descargar ZIP y extraer          | Extraer en carpeta de salida al `complete`; UX de Phase 13 intacta; cero cambios backend | ✓          |
| Guardar el ZIP tal cual          | Más simple, pero el usuario tendría que descomprimir a mano                              |            |
| Guardado incremental por archivo | Requiere tocar el backend (eventos sin contenido)                                        |            |

**User's choice:** Descargar ZIP y extraer

| Option                                | Description                                                | Selected   |
| ------------------------------------- | ---------------------------------------------------------- | ---------- |
| Solo los .md traducidos               | Carpeta de salida limpia; errores ya visibles en la sheet  | ✓          |
| Extraer todo                          | Incluye validation.json y errors.json; útil para auditoría |            |
| .md + errors.json solo si hubo fallos | Compromiso                                                 |            |

**User's choice:** Solo los .md traducidos

| Option               | Description                                               | Selected   |
| -------------------- | --------------------------------------------------------- | ---------- |
| Sobrescribir         | Comportamiento actual de `saveFileSilently`; sin diálogos | ✓          |
| Sufijo único         | Nunca se pierde una traducción previa; acumula duplicados |            |
| Preguntar al usuario | Rompe el flujo silencioso                                 |            |

**User's choice:** Sobrescribir

---

## Cancelación

| Option                | Description                                                                          | Selected   |
| --------------------- | ------------------------------------------------------------------------------------ | ---------- |
| Guardarlos            | ZIP parcial extraído; el coste de API pagado no se tira; resumen "Cancelado: N de M" | ✓          |
| Descartar todo        | «Cancelado significa cancelado», pero pierde traducciones pagadas                    |            |
| Preguntar al cancelar | Un paso extra                                                                        |            |

**User's choice:** Guardar los archivos ya traducidos

| Option                       | Description                                                                                   | Selected   |
| ---------------------------- | --------------------------------------------------------------------------------------------- | ---------- |
| Estado "Cancelando…"         | Botón deshabilitado + "terminando archivo en curso…" hasta `complete`; honesto con el backend | ✓          |
| Cierre inmediato de la sheet | Más brusco; sin confirmación ni resumen parcial                                               |            |

**User's choice:** Estado "Cancelando…"

| Option                | Description                                                 | Selected   |
| --------------------- | ----------------------------------------------------------- | ---------- |
| Avisar antes de salir | Alert "Hay un lote en curso (N de M). ¿Salir y cancelarlo?" | ✓          |
| Salir sin avisar      | Un lote grande se perdería en silencio                      |            |

**User's choice:** Avisar antes de salir con ⌘Q

---

## Entrada del lote

| Option                               | Description                                                              | Selected   |
| ------------------------------------ | ------------------------------------------------------------------------ | ---------- |
| Dock + menú "Traducir lote…"         | Arrastre al Dock + File → Traducir lote… con NSOpenPanel multi-selección | ✓          |
| Solo arrastre al Dock (actual)       | Mínimo alcance                                                           |            |
| Dock + menú + drag&drop a la ventana | Más superficie de entrada, más código                                    |            |

**User's choice:** Dock + menú "Traducir lote…"

| Option                         | Description                                                       | Selected   |
| ------------------------------ | ----------------------------------------------------------------- | ---------- |
| Un idioma (default de Ajustes) | Como hoy (`defaultTargetLang`); la web cubre el caso multi-idioma | ✓          |
| Multi-idioma en el diálogo     | Más paridad con la web, más UI nueva                              |            |

**User's choice:** Un idioma destino

| Option                                 | Description                                                                             | Selected   |
| -------------------------------------- | --------------------------------------------------------------------------------------- | ---------- |
| Confirmación dentro de la sheet        | Estado "preparado": lista de archivos + idioma + botón "Traducir"; sustituye al NSAlert | ✓          |
| Mantener NSAlert + sheet solo progreso | Dos UIs distintas para el mismo flujo                                                   |            |

**User's choice:** Confirmación dentro de la sheet

---

## Claude's Discretion

- Arquitectura Swift interna del cliente SSE (parser de `URLSession.bytes`, observable del estado del job)
- Manejo de reconexión/errores de red del stream SSE
- Detalles visuales de la sheet siguiendo el estilo existente
- Mecanismo de extracción del ZIP (`Process` + `/usr/bin/unzip` vs parser Swift) — a resolver en research

## Deferred Ideas

- Multi-idioma destino en el lote nativo (el jobs API ya lo soporta)
- Drag & drop de varios `.md` sobre la ventana principal como entrada adicional
- Lista completa de archivos con estado individual en la sheet (lotes muy grandes)
