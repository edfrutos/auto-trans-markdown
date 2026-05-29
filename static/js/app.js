/**
 * MarkDown Auto Translator — cliente web
 */

const SAMPLE_MD = `# Getting Started

Welcome to the project! Let's **dive in** and see how things work.

> Tip: This is a handy shortcut you'll use all the time.

## Installation

Run the following command:

\`\`\`bash
npm install my-package
\`\`\`

Don't forget to set your \`API_KEY\` in the config file.

## Features

- Fast and reliable
- [Documentation](https://example.com/docs)
- Works out of the box

| Column | Description |
|--------|-------------|
| speed  | Lightning fast |
| ease   | Piece of cake |
`;

const state = {
  mode: 'editor',
  selectedFile: null,
  batchFiles: [],
  downloadBlob: null,
  downloadName: 'traduccion.md',
  loading: false,
  languagesLoaded: false,
  glossary: { loaded: false, entries: [], dirty: false, expanded: false },
  lastValidation: null,
  batchJobId: null,
  batchJobActive: false,
  eventSource: null,
  estimateController: null,
  batchFileStates: [],
  batchCompletedFiles: 0,
  batchActiveProgress: { done: 0, total: 1 },
  targetLangs: [],
  langNames: {},
};

const $ = (sel) => document.querySelector(sel);

/** Evita crash si el HTML en caché no incluye nodos de fases nuevas. */
function setHtml(el, html) {
  if (el) el.innerHTML = html;
}

const els = {
  sourceLang: $('#source-lang'),
  targetLang: $('#target-lang'),
  targetLangChips: $('#target-lang-chips'),
  inputMd: $('#input-md'),
  outputMd: $('#output-md'),
  btnTranslate: $('#btn-translate'),
  btnTranslateLabel: $('#btn-translate-label'),
  btnCopy: $('#btn-copy'),
  btnDownload: $('#btn-download'),
  btnSample: $('#btn-sample'),
  status: $('#status'),
  progressWrap: $('#progress-wrap'),
  progressBar: $('#progress-bar'),
  progressText: $('#progress-text'),
  fileInput: $('#file-input'),
  dropZone: $('#drop-zone'),
  fileName: $('#file-name'),
  batchInput: $('#batch-input'),
  dropZoneBatch: $('#drop-zone-batch'),
  batchList: $('#batch-list'),
  estimateBatch: $('#estimate-batch'),
  estimateWarn: $('#estimate-warn'),
  estimateFile: $('#estimate-file'),
  estimateWarnFile: $('#estimate-warn-file'),
  batchProgressSection: $('#batch-progress-section'),
  batchProgressBar: $('#batch-progress-bar'),
  batchProgressText: $('#batch-progress-text'),
  batchFileProgressList: $('#batch-file-progress-list'),
  btnCancelJob: $('#btn-cancel-job'),
  themeToggle: $('#theme-toggle'),
  iconSun: $('#icon-sun'),
  iconMoon: $('#icon-moon'),
  glossaryToggle: $('#glossary-toggle'),
  glossaryPanel: $('#glossary-panel'),
  glossaryChevron: $('#glossary-chevron'),
  glossaryTbody: $('#glossary-tbody'),
  btnAddGlossary: $('#btn-add-glossary'),
  btnSaveGlossary: $('#btn-save-glossary'),
  btnClearMemory: $('#btn-clear-memory'),
  previewSource: $('#preview-source'),
  previewResult: $('#preview-result'),
  validationSection: $('#validation-section'),
  validationToggle: $('#validation-toggle'),
  validationPanel: $('#validation-panel'),
  validationChevron: $('#validation-chevron'),
  validationSummary: $('#validation-summary'),
  validationChecks: $('#validation-checks'),
};

const CHECK_LABELS = {
  fences: 'Bloques de código',
  links: 'Enlaces',
  images: 'Imágenes',
  inline_code: 'Código inline',
  headings: 'Encabezados',
};

const tabs = [
  { tab: $('#tab-editor'), panel: $('#panel-editor'), mode: 'editor' },
  { tab: $('#tab-file'), panel: $('#panel-file'), mode: 'file' },
  { tab: $('#tab-batch'), panel: $('#panel-batch'), mode: 'batch' },
];

function showStatus(message, type = 'success') {
  if (!els.status) return;
  els.status.textContent = message;
  els.status.className = `mt-4 rounded-xl px-4 py-3 text-sm ${type}`;
  els.status.classList.remove('hidden');
}

function hideStatus() {
  els.status?.classList.add('hidden');
}

function debounce(fn, ms) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

function renderEstimateBlock(el, warnEl, data) {
  if (!el) return;
  if (!data) {
    el.classList.add('hidden');
    warnEl?.classList.add('hidden');
    return;
  }
  el.classList.remove('hidden');
  const langNote =
    data.language_count > 1 ? ` · ${data.language_count} idiomas` : '';
  el.textContent = `~${data.segments} segmentos · ~${data.characters} chars · ~$${Number(data.estimated_cost_usd).toFixed(2)} (${data.model})${langNote}`;
  if (warnEl) {
    if (data.exceeds_threshold) {
      warnEl.textContent = `Estimación por encima del umbral ($${Number(data.threshold_usd).toFixed(2)})`;
      warnEl.classList.remove('hidden');
    } else {
      warnEl.classList.add('hidden');
    }
  }
}

function appendTargetLangsToForm(form) {
  if (!state.targetLangs.length) return;
  form.append('target_lang', state.targetLangs[0]);
  state.targetLangs.forEach((lang) => form.append('target_langs', lang));
}

function renderTargetChips() {
  if (!els.targetLangChips) return;
  setHtml(
    els.targetLangChips,
    state.targetLangs
      .map((code) => {
        const name = state.langNames[code] || code;
        const removable = state.targetLangs.length > 1;
        return `<span class="lang-chip" data-lang="${code}"><span>${name}</span>${
          removable
            ? `<button type="button" class="lang-chip-remove" aria-label="Quitar ${name}">×</button>`
            : ''
        }</span>`;
      })
      .join('')
  );
  els.targetLangChips.querySelectorAll('.lang-chip-remove').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      const chip = e.target.closest('.lang-chip');
      const code = chip?.getAttribute('data-lang');
      if (!code || state.targetLangs.length <= 1) return;
      state.targetLangs = state.targetLangs.filter((l) => l !== code);
      renderTargetChips();
      if (state.glossary.loaded) loadGlossary();
      scheduleEstimateBatch();
      scheduleEstimateFile();
    });
  });
}

function addTargetLang(code) {
  if (!code || state.targetLangs.includes(code)) return;
  state.targetLangs.push(code);
  renderTargetChips();
  if (state.glossary.loaded) loadGlossary();
  scheduleEstimateBatch();
  scheduleEstimateFile();
}

async function fetchEstimateBatch() {
  if (!els.estimateBatch) return;
  if (!state.batchFiles.length) {
    renderEstimateBlock(els.estimateBatch, els.estimateWarn, null);
    return;
  }
  state.estimateController?.abort();
  state.estimateController = new AbortController();
  const form = new FormData();
  state.batchFiles.forEach((f) => form.append('files', f));
  appendTargetLangsToForm(form);
  form.append('source_lang', els.sourceLang.value);
  try {
    const res = await fetch('/api/translate/estimate', {
      method: 'POST',
      body: form,
      signal: state.estimateController.signal,
    });
    if (!res.ok) return;
    const data = await res.json();
    renderEstimateBlock(els.estimateBatch, els.estimateWarn, data);
  } catch (err) {
    if (err.name !== 'AbortError') {
      renderEstimateBlock(els.estimateBatch, els.estimateWarn, null);
    }
  }
}

async function fetchEstimateFile() {
  if (!els.estimateFile) return;
  if (!state.selectedFile) {
    renderEstimateBlock(els.estimateFile, els.estimateWarnFile, null);
    return;
  }
  state.estimateController?.abort();
  state.estimateController = new AbortController();
  const form = new FormData();
  form.append('files', state.selectedFile);
  appendTargetLangsToForm(form);
  form.append('source_lang', els.sourceLang.value);
  try {
    const res = await fetch('/api/translate/estimate', {
      method: 'POST',
      body: form,
      signal: state.estimateController.signal,
    });
    if (!res.ok) return;
    const data = await res.json();
    renderEstimateBlock(els.estimateFile, els.estimateWarnFile, data);
  } catch (err) {
    if (err.name !== 'AbortError') {
      renderEstimateBlock(els.estimateFile, els.estimateWarnFile, null);
    }
  }
}

const scheduleEstimateBatch = debounce(fetchEstimateBatch, 300);
const scheduleEstimateFile = debounce(fetchEstimateFile, 300);

function resetBatchJobUI() {
  state.batchJobId = null;
  state.batchJobActive = false;
  state.batchFileStates = [];
  state.batchCompletedFiles = 0;
  state.batchActiveProgress = { done: 0, total: 1 };
  if (state.eventSource) {
    state.eventSource.close();
    state.eventSource = null;
  }
  els.batchProgressSection?.classList.add('hidden');
  if (els.batchProgressBar) {
    els.batchProgressBar.style.width = '0%';
    els.batchProgressBar.setAttribute('aria-valuenow', '0');
  }
  if (els.batchProgressText) els.batchProgressText.textContent = '';
  setHtml(els.batchFileProgressList, '');
  if (els.btnTranslate) els.btnTranslate.disabled = !state.languagesLoaded;
}

function updateBatchGlobalProgress() {
  const langCount = state.targetLangs.length || 1;
  const total = (state.batchFiles.length || 1) * langCount;
  const activeFrac =
    state.batchActiveProgress.total > 0
      ? state.batchActiveProgress.done / state.batchActiveProgress.total
      : 0;
  const pct = ((state.batchCompletedFiles + activeFrac) / total) * 100;
  if (els.batchProgressBar) {
    els.batchProgressBar.style.width = `${Math.min(100, pct)}%`;
    els.batchProgressBar.setAttribute('aria-valuenow', String(Math.round(pct)));
  }
}

function initBatchFileList() {
  if (!els.batchFileProgressList) return;
  state.batchFileStates = state.batchFiles.map((f) => ({
    name: f.name,
    langs: state.targetLangs.map((lang) => ({
      lang,
      status: 'pending',
    })),
  }));
  setHtml(
    els.batchFileProgressList,
    state.batchFileStates
      .map(
        (f) =>
          `<li class="batch-file-pending" data-file="${f.name}">${f.name}<ul class="batch-lang-list">${f.langs
            .map(
              (l) =>
                `<li class="batch-lang-pending" data-lang="${l.lang}">${state.langNames[l.lang] || l.lang}</li>`
            )
            .join('')}</ul></li>`
      )
      .join('')
  );
}

function setBatchLangStatus(filename, lang, status) {
  const li = els.batchFileProgressList?.querySelector(
    `[data-file="${CSS.escape(filename)}"] [data-lang="${CSS.escape(lang)}"]`
  );
  if (!li) return;
  li.className = `batch-lang-${status}`;
}

function setBatchFileStatus(filename, status) {
  const li = els.batchFileProgressList?.querySelector(
    `[data-file="${CSS.escape(filename)}"]`
  );
  if (!li) return;
  li.className = `batch-file-${status}`;
}

async function downloadBatchJobResult(jobId) {
  const res = await fetch(`/api/translate/batch/jobs/${jobId}/download`);
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(apiErrorMessage(err, 'No se pudo descargar el ZIP'));
  }
  state.downloadBlob = await res.blob();
  state.downloadName = 'traducciones.zip';
  els.btnDownload?.classList.remove('hidden');
}

async function cancelBatchJob() {
  if (!state.batchJobId) return;
  if (!confirm('¿Cancelar la traducción en curso?')) return;
  try {
    await fetch(`/api/translate/batch/jobs/${state.batchJobId}`, {
      method: 'DELETE',
    });
  } catch {
    /* ignore */
  }
}

function setLoading(loading, text = 'Traduciendo…') {
  state.loading = loading;
  if (els.btnTranslate) {
    els.btnTranslate.disabled = loading || !state.languagesLoaded;
  }
  if (els.btnTranslateLabel) {
    els.btnTranslateLabel.textContent = loading ? text : 'Traducir';
  }
  if (loading) {
    els.progressWrap?.classList.remove('hidden');
    if (els.progressBar) els.progressBar.style.width = '30%';
    if (els.progressText) els.progressText.textContent = 'Procesando con IA…';
  } else {
    if (els.progressBar) els.progressBar.style.width = '100%';
    setTimeout(() => {
      els.progressWrap?.classList.add('hidden');
      if (els.progressBar) els.progressBar.style.width = '0%';
    }, 400);
  }
}

function apiErrorMessage(err, fallback) {
  if (!err) return fallback;
  if (typeof err.detail === 'string') return err.detail;
  if (typeof err.detail === 'object' && err.detail !== null && !Array.isArray(err.detail)) {
    return err.detail.message || fallback;
  }
  if (Array.isArray(err.detail)) {
    return err.detail.map((d) => d.msg || String(d)).join('; ');
  }
  return fallback;
}

function pairKey() {
  const src = els.sourceLang.value || 'auto';
  const tgt = state.targetLangs[0] || els.targetLang.value;
  return `${src}-${tgt}`;
}

function flattenGlossary(data) {
  const entries = [];
  for (const term of data.do_not_translate || []) {
    entries.push({ term, translation: '', dnt: true });
  }
  const pk = pairKey();
  const pairs = data.pairs?.[pk] || data.pairs?.[`auto-${state.targetLangs[0] || els.targetLang.value}`] || {};
  for (const [term, translation] of Object.entries(pairs)) {
    entries.push({ term, translation, dnt: false });
  }
  return entries;
}

function assembleGlossaryPayload() {
  const do_not_translate = [];
  const pairs = {};
  const key = pairKey();
  pairs[key] = {};
  for (const row of state.glossary.entries) {
    const term = (row.term || '').trim();
    if (!term) continue;
    if (row.dnt) {
      do_not_translate.push(term);
    } else if ((row.translation || '').trim()) {
      pairs[key][term] = row.translation.trim();
    }
  }
  if (Object.keys(pairs[key]).length === 0) {
    delete pairs[key];
  }
  return { version: 1, do_not_translate, pairs };
}

function hasGlossaryUi() {
  return Boolean(els.glossaryTbody);
}

function renderGlossaryTable() {
  if (!hasGlossaryUi()) return;
  if (!state.glossary.entries.length) {
    setHtml(
      els.glossaryTbody,
      `<tr><td colspan="4" class="text-ink-muted text-sm py-4 text-center">
        No hay entradas. Añade términos para forzar traducciones consistentes.
      </td></tr>`
    );
    return;
  }
  setHtml(
    els.glossaryTbody,
    state.glossary.entries
    .map(
      (row, i) => `
    <tr data-idx="${i}">
      <td class="px-3 py-2"><input type="text" class="input-inline glossary-term" value="${escapeAttr(row.term)}" placeholder="API Gateway"></td>
      <td class="px-3 py-2"><input type="text" class="input-inline glossary-trans" value="${escapeAttr(row.translation)}" placeholder="panel" ${row.dnt ? 'disabled' : ''}></td>
      <td class="px-3 py-2 text-center"><input type="checkbox" class="glossary-dnt" ${row.dnt ? 'checked' : ''} aria-label="No traducir"></td>
      <td class="px-3 py-2 text-center">
        <button type="button" class="text-ink-muted hover:text-red-600 glossary-remove" aria-label="Eliminar entrada">✕</button>
      </td>
    </tr>`
    )
      .join('')
  );
  bindGlossaryRowEvents();
}

function escapeAttr(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;');
}

function renderPreview(markdown, el) {
  if (!el) return;
  if (typeof marked === 'undefined' || typeof DOMPurify === 'undefined') {
    el.textContent = 'Vista previa no disponible';
    return;
  }
  const raw = marked.parse(markdown || '', { gfm: true, breaks: false });
  el.innerHTML = DOMPurify.sanitize(raw, {
    USE_PROFILES: { html: true },
    FORBID_TAGS: ['script', 'iframe'],
  });
}

function renderValidationPanel(validation) {
  if (!els.validationSection) return;
  if (!validation) {
    els.validationSection.classList.add('hidden');
    return;
  }
  state.lastValidation = validation;
  const counts = { pass: 0, warn: 0, error: 0 };
  for (const check of validation.checks || []) {
    if (counts[check.status] !== undefined) counts[check.status] += 1;
  }
  if (els.validationSummary) {
    els.validationSummary.textContent =
      `${counts.pass} correctos · ${counts.warn} avisos · ${counts.error} errores`;
  }
  if (els.validationChecks) {
    setHtml(
      els.validationChecks,
      (validation.checks || [])
        .map((check) => {
          const icon =
            check.status === 'pass' ? '✓' : check.status === 'warn' ? '⚠' : '✗';
          const color =
            check.status === 'pass'
              ? 'text-teal-600'
              : check.status === 'warn'
                ? 'text-amber-600'
                : 'text-red-600';
          const label = CHECK_LABELS[check.id] || check.id;
          return `<li class="flex gap-2 items-start"><span class="${color}" aria-hidden="true">${icon}</span><span><strong>${label}:</strong> ${escapeAttr(check.message)}</span></li>`;
        })
        .join('')
    );
  }
  els.validationSection.classList.remove('hidden');
}

function bindGlossaryRowEvents() {
  els.glossaryTbody.querySelectorAll('tr[data-idx]').forEach((tr) => {
    const idx = Number(tr.dataset.idx);
    const termIn = tr.querySelector('.glossary-term');
    const transIn = tr.querySelector('.glossary-trans');
    const dntIn = tr.querySelector('.glossary-dnt');
    const markDirty = () => {
      state.glossary.dirty = true;
      state.glossary.entries[idx] = {
        term: termIn.value,
        translation: transIn.value,
        dnt: dntIn.checked,
      };
    };
    termIn?.addEventListener('input', markDirty);
    transIn?.addEventListener('input', markDirty);
    dntIn?.addEventListener('change', () => {
      transIn.disabled = dntIn.checked;
      if (dntIn.checked) transIn.value = '';
      markDirty();
    });
    tr.querySelector('.glossary-remove')?.addEventListener('click', () => {
      state.glossary.entries.splice(idx, 1);
      state.glossary.dirty = true;
      renderGlossaryTable();
    });
  });
}

async function loadGlossary() {
  if (!hasGlossaryUi()) return;
  try {
    const res = await fetch('/api/glossary');
    if (!res.ok) throw new Error('No se pudo cargar el glosario');
    const data = await res.json();
    state.glossary.entries = flattenGlossary(data);
    state.glossary.loaded = true;
    state.glossary.dirty = false;
    renderGlossaryTable();
  } catch (err) {
    showStatus(err.message || 'Error al cargar glosario', 'error');
  }
}

async function saveGlossary() {
  if (!els.btnSaveGlossary) return;
  els.btnSaveGlossary.disabled = true;
  const prev = els.btnSaveGlossary.textContent;
  els.btnSaveGlossary.textContent = 'Guardando…';
  try {
    const body = assembleGlossaryPayload();
    const res = await fetch('/api/glossary', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(apiErrorMessage(data, 'Error al guardar glosario'));
    state.glossary.dirty = false;
    state.glossary.entries = flattenGlossary(data);
    renderGlossaryTable();
    showStatus('Glosario guardado correctamente', 'success');
  } catch (err) {
    showStatus(err.message, 'error');
  } finally {
    els.btnSaveGlossary.disabled = false;
    els.btnSaveGlossary.textContent = prev;
  }
}

async function clearMemory() {
  if (
    !confirm(
      '¿Eliminar todas las traducciones en cache? Esta acción no se puede deshacer.'
    )
  ) {
    return;
  }
  try {
    const res = await fetch('/api/memory', { method: 'DELETE' });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(apiErrorMessage(data, 'Error al limpiar memoria'));
    showStatus('Memoria de traducción vaciada', 'success');
  } catch (err) {
    showStatus(err.message, 'error');
  }
}

async function loadLanguages() {
  if (!els.targetLang || !els.sourceLang) {
    console.error('MarkDown Auto Translator: faltan selectores de idioma en el DOM');
    return;
  }
  if (els.btnTranslate) els.btnTranslate.disabled = true;
  els.targetLang.setAttribute('aria-busy', 'true');
  try {
    const res = await fetch('/api/languages');
    if (!res.ok) throw new Error('No se pudieron cargar los idiomas');
    const langs = await res.json();
    state.langNames = {};
    setHtml(els.targetLang, '');
    const addOpt = document.createElement('option');
    addOpt.value = '';
    addOpt.textContent = 'Añadir idioma…';
    addOpt.disabled = true;
    addOpt.selected = true;
    els.targetLang.appendChild(addOpt);
    setHtml(els.sourceLang, '<option value="auto">Detectar automáticamente</option>');
    let defaultCode = null;
    for (const { code, name } of langs) {
      if (code === 'auto') continue;
      state.langNames[code] = name;
      const optTarget = document.createElement('option');
      optTarget.value = code;
      optTarget.textContent = name;
      els.targetLang.appendChild(optTarget);
      if (code === 'es') defaultCode = code;

      const optSource = document.createElement('option');
      optSource.value = code;
      optSource.textContent = name;
      els.sourceLang.appendChild(optSource);
    }
    if (!defaultCode) {
      const first = langs.find((l) => l.code !== 'auto');
      defaultCode = first?.code || null;
    }
    state.targetLangs = defaultCode ? [defaultCode] : [];
    renderTargetChips();
    state.languagesLoaded = true;
    if (els.btnTranslate) els.btnTranslate.disabled = false;
    els.targetLang.removeAttribute('aria-busy');
    await loadGlossary();
  } catch (err) {
    state.languagesLoaded = false;
    els.targetLang.removeAttribute('aria-busy');
    setHtml(els.targetLang, '');
    const opt = document.createElement('option');
    opt.value = '';
    opt.textContent = 'Error al cargar idiomas';
    opt.disabled = true;
    els.targetLang.appendChild(opt);
    showStatus(err.message || 'No se pudieron cargar los idiomas desde la API.', 'error');
  }
}

function switchTab(mode) {
  state.mode = mode;
  tabs.forEach(({ tab, panel, mode: m }) => {
    if (!tab || !panel) return;
    const active = m === mode;
    tab.setAttribute('aria-selected', String(active));
    tab.classList.toggle('tab-btn-active', active);
    panel.classList.toggle('hidden', !active);
  });
  els.btnDownload?.classList.add('hidden');
  hideStatus();
}

async function translateEditor() {
  const content = els.inputMd.value.trim();
  if (!content) {
    showStatus('Escribe o pega contenido Markdown primero.', 'error');
    return;
  }
  hideStatus();
  setLoading(true);
  try {
    const res = await fetch('/api/translate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content,
        target_lang: state.targetLangs[0],
        target_langs: state.targetLangs,
        source_lang: els.sourceLang.value,
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(apiErrorMessage(data, 'Error de traducción'));
    const primary = state.targetLangs[0];
    const result = data.translations?.[primary] || data;
    els.outputMd.value = result.content;
    els.btnCopy.disabled = false;
    const blob = new Blob([result.content], { type: 'text/markdown;charset=utf-8' });
    state.downloadBlob = blob;
    state.downloadName = `traduccion.${primary}.md`;
    els.btnDownload.classList.remove('hidden');
    renderPreview(content, els.previewSource);
    renderPreview(result.content, els.previewResult);
    renderValidationPanel(result.validation);
    const langCount = data.translations ? state.targetLangs.length : 1;
    showStatus(
      langCount > 1
        ? `Listo — ${langCount} idiomas traducidos (mostrando ${state.langNames[primary] || primary}).`
        : `Listo — ${result.segments_translated} segmentos traducidos.`
    );
  } catch (err) {
    showStatus(err.message, 'error');
  } finally {
    setLoading(false);
  }
}

async function translateFile() {
  if (!state.selectedFile) {
    showStatus('Selecciona un archivo .md primero.', 'error');
    return;
  }
  hideStatus();
  setLoading(true);
  const form = new FormData();
  form.append('file', state.selectedFile);
  appendTargetLangsToForm(form);
  form.append('source_lang', els.sourceLang.value);
  try {
    const res = await fetch('/api/translate/file', { method: 'POST', body: form });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(apiErrorMessage(err, 'Error al traducir archivo'));
    }
    const blob = await res.blob();
    const disposition = res.headers.get('Content-Disposition') || '';
    const match = disposition.match(/filename="?([^"]+)"?/);
    state.downloadBlob = blob;
    state.downloadName = match
      ? match[1]
      : `traduccion.${state.targetLangs[0]}.md`;
    const contentType = res.headers.get('Content-Type') || '';
    if (contentType.includes('zip')) {
      els.outputMd.value = '';
      els.btnCopy.disabled = true;
      renderPreview(await state.selectedFile.text(), els.previewSource);
      renderPreview('', els.previewResult);
      renderValidationPanel(null);
      showStatus(
        `ZIP listo (${state.targetLangs.length} idiomas): ${state.downloadName}`
      );
    } else {
      const text = await blob.text();
      els.outputMd.value = text;
      els.btnCopy.disabled = false;
      renderPreview(await state.selectedFile.text(), els.previewSource);
      renderPreview(text, els.previewResult);
      const valHeader = res.headers.get('X-Validation-Report');
      if (valHeader) {
        try {
          renderValidationPanel(JSON.parse(valHeader));
        } catch {
          renderValidationPanel(null);
        }
      }
      showStatus(`Archivo traducido: ${state.downloadName}`);
    }
    els.btnDownload.classList.remove('hidden');
  } catch (err) {
    showStatus(err.message, 'error');
  } finally {
    setLoading(false);
  }
}

async function translateBatch() {
  if (!state.batchFiles.length) {
    showStatus('Añade al menos un archivo al lote.', 'error');
    return;
  }
  hideStatus();
  resetBatchJobUI();
  state.batchJobActive = true;
  if (els.btnTranslate) els.btnTranslate.disabled = true;
  els.batchProgressSection?.classList.remove('hidden');
  initBatchFileList();
  if (els.batchProgressText) {
    els.batchProgressText.textContent = 'Iniciando lote…';
  }

  const form = new FormData();
  state.batchFiles.forEach((f) => form.append('files', f));
  appendTargetLangsToForm(form);
  form.append('source_lang', els.sourceLang.value);

  try {
    const res = await fetch('/api/translate/batch/jobs', {
      method: 'POST',
      body: form,
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(apiErrorMessage(err, 'Error al iniciar lote'));
    }
    const { job_id: jobId } = await res.json();
    state.batchJobId = jobId;

    await new Promise((resolve, reject) => {
      const es = new EventSource(
        `/api/translate/batch/jobs/${jobId}/events`
      );
      state.eventSource = es;

      es.onmessage = async (msg) => {
        let event;
        try {
          event = JSON.parse(msg.data);
        } catch {
          return;
        }
        const type = event.type;
        if (type === 'file_start') {
          setBatchFileStatus(event.filename, 'active');
          if (event.target_lang) {
            setBatchLangStatus(event.filename, event.target_lang, 'active');
          }
          state.batchActiveProgress = { done: 0, total: event.total_files || 1 };
          if (els.batchProgressText) {
            const langLabel = event.target_lang
              ? ` · ${state.langNames[event.target_lang] || event.target_lang}`
              : '';
            els.batchProgressText.textContent = `Traduciendo ${event.filename}${langLabel} (${event.file_index + 1}/${event.total_files})…`;
          }
          updateBatchGlobalProgress();
        } else if (type === 'segment_progress') {
          state.batchActiveProgress = {
            done: event.done,
            total: event.total || 1,
          };
          if (els.batchProgressText) {
            const langLabel = event.target_lang
              ? ` (${state.langNames[event.target_lang] || event.target_lang})`
              : '';
            els.batchProgressText.textContent = `${event.filename}${langLabel}: ${event.done}/${event.total} segmentos`;
          }
          updateBatchGlobalProgress();
        } else if (type === 'file_done') {
          if (event.target_lang) {
            setBatchLangStatus(event.filename, event.target_lang, 'ok');
          }
          state.batchCompletedFiles += 1;
          state.batchActiveProgress = { done: 0, total: 1 };
          updateBatchGlobalProgress();
        } else if (type === 'error') {
          if (event.target_lang) {
            setBatchLangStatus(event.filename, event.target_lang, 'error');
          } else {
            setBatchFileStatus(event.filename, 'error');
          }
          state.batchCompletedFiles += 1;
          updateBatchGlobalProgress();
        } else if (type === 'complete') {
          es.close();
          state.eventSource = null;
          const ok = event.ok_count ?? 0;
          const total = event.total_files ?? state.batchFiles.length;
          const errors = event.error_count ?? 0;
          if (event.cancelled) {
            showStatus(
              `Cancelado: ${ok}/${total} archivos OK${errors ? ` — ${errors} errores` : ''}. Puedes descargar el ZIP parcial.`,
              errors ? 'warning' : 'success'
            );
          } else if (errors > 0) {
            showStatus(
              `${ok}/${total} OK — ${errors} errores. Revisa errors.json en el ZIP.`,
              'warning'
            );
          } else {
            showStatus(`${ok} archivos traducidos — validation.json incluido en ZIP.`);
          }
          try {
            await downloadBatchJobResult(jobId);
          } catch (err) {
            showStatus(err.message, 'error');
          }
          resetBatchJobUI();
          resolve();
        }
      };

      es.onerror = () => {
        es.close();
        reject(new Error('Conexión SSE interrumpida'));
      };
    });
  } catch (err) {
    showStatus(err.message, 'error');
    resetBatchJobUI();
  }
}

function handleTranslate() {
  if (state.mode === 'editor') return translateEditor();
  if (state.mode === 'file') return translateFile();
  return translateBatch();
}

function downloadResult() {
  if (!state.downloadBlob) return;
  const url = URL.createObjectURL(state.downloadBlob);
  const a = document.createElement('a');
  a.href = url;
  a.download = state.downloadName;
  a.click();
  URL.revokeObjectURL(url);
}

function setupDropZone(zone, input, onFiles) {
  zone.addEventListener('click', () => input.click());
  zone.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      input.click();
    }
  });
  zone.addEventListener('dragover', (e) => {
    e.preventDefault();
    zone.classList.add('drag-over');
  });
  zone.addEventListener('dragleave', () => zone.classList.remove('drag-over'));
  zone.addEventListener('drop', (e) => {
    e.preventDefault();
    zone.classList.remove('drag-over');
    onFiles(e.dataTransfer.files);
  });
  input.addEventListener('change', () => onFiles(input.files));
}

function initTheme() {
  const stored = localStorage.getItem('theme');
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  const dark = stored === 'dark' || (!stored && prefersDark);
  document.documentElement.classList.toggle('dark', dark);
  els.iconSun?.classList.toggle('hidden', !dark);
  els.iconMoon?.classList.toggle('hidden', dark);
}

function toggleTheme() {
  const isDark = document.documentElement.classList.toggle('dark');
  localStorage.setItem('theme', isDark ? 'dark' : 'light');
  els.iconSun.classList.toggle('hidden', !isDark);
  els.iconMoon.classList.toggle('hidden', isDark);
}

// Event listeners
tabs.forEach(({ tab, mode }) => tab?.addEventListener('click', () => switchTab(mode)));
els.btnTranslate?.addEventListener('click', handleTranslate);
els.btnDownload?.addEventListener('click', downloadResult);
els.btnSample?.addEventListener('click', () => {
  els.inputMd.value = SAMPLE_MD;
  renderPreview(SAMPLE_MD, els.previewSource);
  if (els.previewResult) els.previewResult.innerHTML = '';
});
els.btnCopy?.addEventListener('click', async () => {
  await navigator.clipboard.writeText(els.outputMd.value);
  showStatus('Copiado al portapapeles.');
});
els.themeToggle?.addEventListener('click', toggleTheme);

els.glossaryToggle?.addEventListener('click', () => {
  const expanded = els.glossaryPanel.classList.toggle('hidden');
  const isOpen = !expanded;
  els.glossaryToggle.setAttribute('aria-expanded', String(isOpen));
  els.glossaryChevron?.classList.toggle('expanded', isOpen);
  state.glossary.expanded = isOpen;
});

els.validationToggle?.addEventListener('click', () => {
  const expanded = els.validationPanel.classList.toggle('hidden');
  const isOpen = !expanded;
  els.validationToggle.setAttribute('aria-expanded', String(isOpen));
  els.validationChevron?.classList.toggle('expanded', isOpen);
});

els.btnAddGlossary?.addEventListener('click', () => {
  state.glossary.entries.push({ term: '', translation: '', dnt: false });
  state.glossary.dirty = true;
  renderGlossaryTable();
});

els.btnSaveGlossary?.addEventListener('click', saveGlossary);
els.btnClearMemory?.addEventListener('click', clearMemory);

els.sourceLang.addEventListener('change', () => {
  if (state.glossary.loaded) loadGlossary();
  scheduleEstimateBatch();
  scheduleEstimateFile();
});
els.targetLang.addEventListener('change', () => {
  const code = els.targetLang.value;
  if (code) addTargetLang(code);
  els.targetLang.selectedIndex = 0;
});

els.btnCancelJob?.addEventListener('click', cancelBatchJob);

if (els.dropZone && els.fileInput) {
  setupDropZone(els.dropZone, els.fileInput, (files) => {
    const f = files[0];
    if (!f) return;
    state.selectedFile = f;
    if (els.fileName) {
      els.fileName.textContent = f.name;
      els.fileName.classList.remove('hidden');
    }
    scheduleEstimateFile();
  });
}

if (els.dropZoneBatch && els.batchInput) {
  setupDropZone(els.dropZoneBatch, els.batchInput, (files) => {
    state.batchFiles = Array.from(files).filter((f) =>
      /\.(md|markdown|mdx)$/i.test(f.name)
    );
    setHtml(
      els.batchList,
      state.batchFiles.map((f) => `<li>${f.name}</li>`).join('')
    );
    els.batchList?.classList.toggle('hidden', !state.batchFiles.length);
    scheduleEstimateBatch();
  });
}

loadLanguages();
initTheme();
