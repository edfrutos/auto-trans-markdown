# Phase 3: Batch UX & Cost Control - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-29
**Phase:** 3-Batch UX & Cost Control
**Areas discussed:** Progreso UI, Fallos parciales, Cancelación, Estimación de coste

---

## Progreso en UI durante lote

| Option | Description | Selected |
|--------|-------------|----------|
| Barra global + lista por archivo | Icono/estado por archivo | ✓ |
| Solo barra global con texto | Archivo N/M · % | |
| Barra global + segmentos del archivo actual | Detalle intra-archivo en texto | |

| Option | Description | Selected |
|--------|-------------|----------|
| Eventos NOTEBOOK completos | file_start, file_done, segment_progress, error, complete | ✓ |
| Solo progreso por archivo | Sin segment_progress | |
| Claude decide | Mínimo JOB-02 | |

| Option | Description | Selected |
|--------|-------------|----------|
| Solo lote con SSE real | Editor/archivo con spinner simple | ✓ |
| Editor y archivo también con progreso real | SSE en todos los modos | |
| Spinner en editor/archivo | Barra real solo lote | |

| Option | Description | Selected |
|--------|-------------|----------|
| Apilado vertical en móvil | Barra arriba, lista scroll | ✓ |
| Lista colapsada en móvil | Solo archivo actual visible | |
| Igual que desktop | | |

**User's choice:** Barra global + lista; eventos NOTEBOOK; SSE solo en lote; móvil apilado.

---

## Lotes con fallos parciales

| Option | Description | Selected |
|--------|-------------|----------|
| Continuar y entregar parcial | ZIP + errors.json | ✓ |
| Abortar al primer error | Sin ZIP parcial | |
| Pausar y preguntar | Usuario decide | |

| Option | Description | Selected |
|--------|-------------|----------|
| filename + mensaje de error | errors.json minimal | ✓ |
| Detalle verbose | stack, segmentos | |
| Solo nombres | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Incluir validation.json de exitosos | Patrón Phase 2 | ✓ |
| Solo .md + errors.json | | |
| validation.json solo si OK | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Estados en lista + resumen final | «8/10 OK — 2 errores» | ✓ |
| Solo mensaje de status | | |
| Modal de errores antes de descargar | | |

**User's choice:** Continuar parcial; errors.json filename+message; validation.json en exitosos; resumen en UI.

---

## Cancelación de job

| Option | Description | Selected |
|--------|-------------|----------|
| Confirmación antes de cancelar | confirm() modal | ✓ |
| Cancelar inmediato | | |
| Doble confirmación en botón | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Ofrecer ZIP parcial | Lo ya completado | ✓ |
| Descartar todo | Sin descarga | |
| Descarga automática del parcial | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Completar archivo en curso y parar | Cancel cooperativa | ✓ |
| Parar inmediatamente | | |
| Esperar fin del archivo actual | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Reset UI + resumen cancelación | Volver a estado inicial | ✓ |
| Mantener lista con estados finales | | |
| Como completo con badge Cancelado | | |

**User's choice:** confirm(); ZIP parcial ofrecido; completar archivo en curso; reset con resumen.

---

## Estimación de coste pre-traducción

| Option | Description | Selected |
|--------|-------------|----------|
| Lote + archivo único | Editor sin estimate | ✓ |
| Solo lote | | |
| Editor, archivo y lote | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Segmentos · chars · coste · modelo | Formato NOTEBOOK | ✓ |
| Solo coste | | |
| Desglose con cache TM | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Umbral configurable en .env | ESTIMATE_WARN_USD | ✓ |
| Sin umbral | Solo informativo | |
| Umbral fijo en código | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Inline — Traducir inicia directo | Sin confirm extra | ✓ |
| Modal de confirmación extra | | |
| Panel colapsable informativo | | |

**User's choice:** Estimate en lote + archivo; formato NOTEBOOK; umbral .env; inline sin confirm extra.

---

## Claude's Discretion

- Rutas exactas endpoints jobs SSE
- Esquema payloads SSE y campos opcionales errors.json
- Tabla de precios por proveedor/modelo
- Default ESTIMATE_WARN_USD
- Progreso CLI batch (mínimo viable)

## Deferred Ideas

- SSE progreso en editor
- Modal confirmación post-estimate
- Desglose ahorro cache en estimate UI
- Redis job store (V2-04)
- Abortar lote al primer error
