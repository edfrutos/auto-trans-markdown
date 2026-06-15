# Phase 2: Trust & QA - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-28
**Phase:** 2-Trust & QA
**Areas discussed:** Validación, Preview, Frontmatter, Comentarios en fences

---

## Validación post-traducción

| Option                            | Description                               | Selected   |
| --------------------------------- | ----------------------------------------- | ---------- |
| Avisos por defecto + --strict CLI | Descarga normal; CLI bloquea con --strict | ✓          |
| Errores por defecto               | Bloquea descarga hasta corregir           |            |
| Solo informativo                  | Nunca bloquea salvo flag futuro           |            |

| Option            | Description                                   | Selected   |
| ----------------- | --------------------------------------------- | ---------- |
| Núcleo 4 checks   | Fences, enlaces/imágenes, inline, encabezados | ✓          |
| Núcleo + longitud | + alerta >300%                                |            |
| Mínimo            | Solo fences y enlaces                         |            |

| Option                          | Description   | Selected   |
| ------------------------------- | ------------- | ---------- |
| Panel colapsable bajo resultado | Como Glosario | ✓          |
| Solo barra de estado            | Sin panel     |            |
| Pestaña Validación              | Nueva pestaña |            |

| Option                             | Description   | Selected   |
| ---------------------------------- | ------------- | ---------- |
| validation.json por archivo en ZIP |               | ✓          |
| Manifest único en raíz             |               |            |
| Solo UI                            |               |            |

**User's choice:** Warnings por defecto; checks núcleo; panel bajo resultado; JSON por archivo en lote.

---

## Vista previa renderizada

| Option                                            | Description                          | Selected   |
| ------------------------------------------------- | ------------------------------------ | ---------- |
| Dos paneles Original / Traducido bajo texto plano |                                      | ✓          |
| Toggle un solo panel                              |                                      |            |
| Pestañas Texto / Preview                          |                                      |            |

| Option                             | Description   | Selected   |
| ---------------------------------- | ------------- | ---------- |
| Al terminar traducción (+ ejemplo) |               | ✓          |
| Debounce al editar                 |               |            |
| Botón manual                       |               |            |

| Option                    | Description   | Selected   |
| ------------------------- | ------------- | ---------- |
| Apilar en móvil           |               | ✓          |
| Ocultar original en móvil |               |            |
| Claude decide             |               |            |

**User's choice:** Dual render debajo; actualizar al traducir; stack vertical en pantallas estrechas.

---

## Frontmatter selectivo

| Option                                                     | Description   | Selected   |
| ---------------------------------------------------------- | ------------- | ---------- |
| title, description, summary + tags + categories + keywords |               | ✓          |
| Solo tres campos ROADMAP                                   |               |            |
| Más campos custom                                          |               |            |

| Option                 | Description   | Selected   |
| ---------------------- | ------------- | ---------- |
| Lista blanca hardcoded |               | ✓          |
| Variable de entorno    |               |            |
| config.yaml            |               |            |

| Option                                  | Description   | Selected   |
| --------------------------------------- | ------------- | ---------- |
| Proteger bloque entero si YAML inválido |               | ✓          |
| Best-effort parcial                     |               |            |

**User's choice:** Whitelist amplia en código; fallback proteger todo el bloque.

---

## Comentarios en fences

| Option                                    | Description   | Selected   |
| ----------------------------------------- | ------------- | ---------- |
| python + js/ts + html/xml (ROADMAP)       |               | ✓          |
| NOTEBOOK completo (+ ruby, java, go, sql) |               |            |
| Solo python + js                          |               |            |

| Option                            | Description   | Selected   |
| --------------------------------- | ------------- | ---------- |
| Claude decide edge cases en tests |               | ✓          |
| Solo líneas comentario puro       |               |            |
| Agresivo por prefijo              |               |            |

**User's choice:** Alcance ROADMAP; edge cases a criterio de tests/plan.

---

## Claude's Discretion

- CDN marked/DOMPurify, esquema JSON validación, contrato API informe, preview en pestaña Archivo.

## Deferred Ideas

- Alerta longitud, frontmatter configurable, lenguajes SQL/ruby/etc., strict en UI, SSE Phase 3, diff Phase 5.
