# Phase 0 — UI Review

**Audited:** 2026-05-28  
**Baseline:** Abstract 6-pillar standards (no UI-SPEC.md for Phase 0)  
**Scope:** Cambios UI en plan 00-03 (`static/index.html`, `static/js/app.js`) + contexto de la app existente  
**Screenshots:** No capturadas (servidor no accesible desde entorno de auditoría; revisión code-only)

---

## Pillar Scores

| Pillar               | Score   | Key Finding                                                  |
| -------------------- | ------- | ------------------------------------------------------------ |
| 1. Copywriting       | 4/4     | Estados de carga/error en español claro y accionable         |
| 2. Visuals           | 3/4     | Placeholder textual en select; sin indicador visual de carga |
| 3. Color             | 4/4     | Sin colores nuevos; tokens CSS/Tailwind coherentes           |
| 4. Typography        | 4/4     | Sin regresiones; escala existente consistente                |
| 5. Spacing           | 4/4     | Sin cambios de espaciado en Phase 0                          |
| 6. Experience Design | 2/4     | Falta bloqueo de acción hasta idiomas listos; sin reintento  |

**Overall: 21/24**

---

## Top 3 Priority Fixes

1. **Deshabilitar «Traducir» hasta que `loadLanguages()` termine con éxito** — Evita POST con `target_lang=""` si el usuario pulsa antes de que carguen los idiomas. En `app.js`, set `els.btnTranslate.disabled = true` al inicio de `loadLanguages()` y habilitar solo tras poblar `#target-lang` con opciones válidas.

2. **Añadir reintento tras fallo de `/api/languages`** — Tras error de red, el select queda en «Error al cargar idiomas» sin acción de recuperación. Añadir botón/enlace «Reintentar» junto al select destino o re-ejecutar `loadLanguages()` al hacer focus en el control.

3. **Feedback de carga accesible en selects de idioma** — Sustituir solo el `<option disabled>Cargando…</option>` por `aria-busy="true"` en `#target-lang` y texto en `#source-lang-hint` («Cargando idiomas disponibles…») para lectores de pantalla y usuarios sighted.

---

## Detailed Findings

### Pillar 1: Copywriting (4/4)

**Phase 0 changes — pass**

- `static/index.html:84` — «Cargando idiomas…» comunica estado de espera sin jerga técnica.
- `static/js/app.js:117-118` — Error fetch: «No se pudieron cargar los idiomas».
- `static/js/app.js:145-148` — Option fallback: «Error al cargar idiomas» + `showStatus` con mensaje de API.
- `apiErrorMessage` (`app.js:102-111`) extrae `detail.message` del JSON 502 — alineado con errores backend en español (HARD-01).

Sin etiquetas genéricas («Submit», «OK») en strings tocados por Phase 0.

### Pillar 2: Visuals (3/4)

**Strengths**

- Jerarquía existente (hero → controles → tabs → paneles) intacta.
- Iconografía decorativa con `aria-hidden="true"` en SVGs del layout principal.

**Gaps (Phase 0 delta)**

- `static/index.html:84` — Estado de carga solo como texto dentro del `<select>`; no hay spinner ni skeleton en la fila de controles.
- Sin diferenciación visual entre «cargando» y «error» más allá del texto del option y el banner `#status`.

**Recommendation:** Indicador inline (spinner 16px o pulse en borde del select) durante fetch.

### Pillar 3: Color (4/4)

- Phase 0 no introduce hex sueltos en HTML/JS.
- Tokens en `static/css/app.css:3-13` y Tailwind extend (`index.html:19-24`) siguen paleta teal/naranja.
- Estados error/success en `#status` usan variables semitransparentes (`app.css:240-254`).

### Pillar 4: Typography (4/4)

Tamaños en `index.html`: `text-xs`, `text-sm`, `text-base`, `text-lg`, `text-3xl`, `text-4xl` — dentro de escala acotada del MVP. Plus Jakarta Sans + monospace en editores — sin cambios Phase 0.

### Pillar 5: Spacing (4/4)

Grid `sm:grid-cols-2 gap-4 mb-6` en controles de idioma (`index.html:73`) coherente con resto de layout. Sin valores arbitrarios `[Npx]` en archivos modificados.

### Pillar 6: Experience Design (2/4)

**Phase 0 improvements — pass partial**

- ✅ Fetch dinámico `/api/languages` elimina desalineación OpenAI/DeepL (HARD-03).
- ✅ Error path visible vía `#status` + option deshabilitado.
- ✅ `apiErrorMessage` maneja `detail` objeto (502 estructurado).

**Gaps**

| Issue                                                | Location                                                            | Impact                                                                         |
| ---------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Botón Traducir activo durante carga/error de idiomas | `app.js:342` — `loadLanguages()` async sin gate en `#btn-translate` | Usuario puede enviar `target_lang=""` → 400 confuso                            |
| Sin reintento tras fallo de idiomas                  | `app.js:141-149` catch solo muestra error                           | Requiere reload de página                                                      |
| Tabs sin navegación por teclado (flechas)            | `index.html:90-95`, `app.js:152-161`                                | Pre-existente; a11y menor                                                      |
| Barra de progreso simulada al 30%                    | `app.js:89-92`                                                      | Pre-existente (Phase 3); fuera de alcance Phase 0 pero afecta percepción de UX |

**Registry audit:** N/A — no shadcn/components.json.

---

## Phase 0 Requirement Alignment (HARD-03 UI)

| Criterio                                         | Verdict                                  |
| ------------------------------------------------ | ---------------------------------------- |
| UI consume `/api/languages` dinámicamente        | ✅ `loadLanguages()`                      |
| Sin listas hardcodeadas desalineadas             | ✅ `index.html` sin destinos fijos        |
| Manejo de error sin fallback estático incorrecto | ✅ Parcial — error visible pero sin retry |

---

## Files Audited

- `static/index.html` (select destino placeholder)
- `static/js/app.js` (`loadLanguages`, `apiErrorMessage`, estados error)
- `static/css/app.css` (tokens, focus-visible, estados — referencia)
- `.planning/phases/00-mvp-hardening/00-03-PLAN.md`
- `.planning/phases/00-mvp-hardening/00-03-SUMMARY.md`
- `.planning/phases/00-mvp-hardening/00-CONTEXT.md` (D-07–D-09)

---

## Verdict

**PASS with minor UX debt** — Los cambios de Phase 0 cumplen HARD-03 a nivel funcional. Las mejoras recomendadas son de pulido UX (gate del botón Traducir, reintento, aria-busy) y pueden abordarse en Phase 1 junto al rediseño de flujos o como fix rápido opcional.
