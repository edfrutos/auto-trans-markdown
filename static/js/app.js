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
  estimateEditorController: null,  // ESTIMATE-01
  batchFileStates: [],
  batchCompletedFiles: 0,
  batchActiveProgress: { done: 0, total: 1 },
  targetLangs: [],
  langNames: {},
  reviewMode: false,
  draftSegments: [],
  sourceContent: '',
  historyEnabled: false,
  translationResults: null,
  activeResultLang: null,
};

const API_TOKEN_KEY = 'md-translate-api-token';

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
  btnDownloadLabel: $('#btn-download-label'),
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
  estimateEditor: $('#estimate-editor'),  // ESTIMATE-01
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
  toneSelect: $('#tone-select'),
  reviewSection: $('#review-section'),
  reviewModeToggle: $('#review-mode-toggle'),
  reviewSegments: $('#review-segments'),
  btnFinalizeReview: $('#btn-finalize-review'),
  tabPreview: $('#tab-preview'),
  tabDiff: $('#tab-diff'),
  previewGrid: $('#preview-grid'),
  diffPanel: $('#diff-panel'),
  btnExportHtml: $('#btn-export-html'),
  btnExportPdf: $('#btn-export-pdf'),
  historyEnabled: $('#history-enabled'),
  btnClearHistory: $('#btn-clear-history'),
  apiTokenToggle: $('#api-token-toggle'),
  apiTokenPanel: $('#api-token-panel'),
  apiTokenChevron: $('#api-token-chevron'),
  apiTokenInput: $('#api-token-input'),
  btnSaveApiToken: $('#btn-save-api-token'),
  btnClearApiToken: $('#btn-clear-api-token'),
  resultLangTabs: $('#result-lang-tabs'),
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

function getApiToken() {
  return localStorage.getItem(API_TOKEN_KEY)?.trim() || '';
}

function setApiToken(value) {
  const v = value?.trim();
  if (v) localStorage.setItem(API_TOKEN_KEY, v);
  else localStorage.removeItem(API_TOKEN_KEY);
}

function authHeaders(extra = {}) {
  const headers = { ...extra };
  const token = getApiToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

async function apiFetch(url, init = {}) {
  const raw = init.headers;
  const base =
    raw instanceof Headers
      ? Object.fromEntries(raw.entries())
      : { ...(raw || {}) };
  const res = await fetch(url, { ...init, headers: authHeaders(base) });
  if (res.status === 401) {
    const err = new Error(
      'No autorizado — configura el token de API en «Token API».'
    );
    err.status = 401;
    throw err;
  }
  return res;
}

function authEventSourceUrl(path) {
  const token = getApiToken();
  if (!token) return path;
  const sep = path.includes('?') ? '&' : '?';
  return `${path}${sep}access_token=${encodeURIComponent(token)}`;
}

function clearResultLangTabs() {
  state.translationResults = null;
  state.activeResultLang = null;
  els.resultLangTabs?.classList.add('hidden');
  setHtml(els.resultLangTabs, '');
}

function renderResultLangTabs() {
  if (!els.resultLangTabs || !state.translationResults) return;
  const langs = Object.keys(state.translationResults);
  if (langs.length <= 1) {
    els.resultLangTabs.classList.add('hidden');
    setHtml(els.resultLangTabs, '');
    return;
  }
  els.resultLangTabs.classList.remove('hidden');
  setHtml(
    els.resultLangTabs,
    langs
      .map((code) => {
        const name = state.langNames[code] || code;
        const active = code === state.activeResultLang;
        return `<button type="button" role="tab" class="result-lang-tab${
          active ? ' active' : ''
        }" data-lang="${code}" aria-selected="${active}">${name}</button>`;
      })
      .join('')
  );
  els.resultLangTabs.querySelectorAll('.result-lang-tab').forEach((btn) => {
    btn.addEventListener('click', () => {
      const lang = btn.getAttribute('data-lang');
      if (lang) showTranslationForLang(lang);
    });
  });
}

function showTranslationForLang(lang) {
  const result = state.translationResults?.[lang];
  if (!result) return;
  state.activeResultLang = lang;
  els.outputMd.value = result.content;
  els.btnCopy.disabled = false;
  const blob = new Blob([result.content], { type: 'text/markdown;charset=utf-8' });
  state.downloadBlob = blob;
  state.downloadName = `traduccion.${lang}.md`;
  showDownloadButton();
  renderPreview(state.sourceContent, els.previewSource);
  renderPreview(result.content, els.previewResult);
  renderDiff(state.sourceContent, result.content);
  renderValidationPanel(result.validation);
  renderResultLangTabs();
  els.btnExportHtml?.classList.remove('hidden');
  els.btnExportPdf?.classList.remove('hidden');
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

function getTone() {
  return els.toneSelect?.value || 'auto';
}

function appendTargetLangsToForm(form) {
  if (!state.targetLangs.length) return;
  form.append('target_lang', state.targetLangs[0]);
  state.targetLangs.forEach((lang) => form.append('target_langs', lang));
  form.append('tone', getTone());
}

const HISTORY_KEY = 'md-translate-history';
const MAX_HISTORY = 50;
const EXPORT_CSS =
  'body{font-family:system-ui,sans-serif;line-height:1.6;max-width:48rem;margin:2rem auto;padding:0 1rem;color:#1e293b}' +
  'h1,h2,h3{color:#0f766e;margin-top:1.5em}pre{background:#f1f5f9;padding:1rem;overflow-x:auto;border-radius:.5rem}' +
  'code{background:#f1f5f9;padding:.1em .35em;border-radius:.25rem;font-size:.9em}' +
  'blockquote{border-left:4px solid #14b8a6;margin-left:0;padding-left:1rem;color:#475569}';

function pushHistory(entry) {
  if (!state.historyEnabled) return;
  try {
    const list = JSON.parse(localStorage.getItem(HISTORY_KEY) || '[]');
    list.unshift({
      ts: Date.now(),
      targetLang: entry.targetLang,
      mode: entry.mode,
      segments: entry.segments,
      chars: entry.chars,
    });
    localStorage.setItem(HISTORY_KEY, JSON.stringify(list.slice(0, MAX_HISTORY)));
    els.btnClearHistory?.classList.remove('hidden');
  } catch {
    /* localStorage no disponible */
  }
}

function initHistory() {
  const stored = localStorage.getItem('md-translate-history-enabled');
  state.historyEnabled = stored === '1';
  if (els.historyEnabled) els.historyEnabled.checked = state.historyEnabled;
  if (state.historyEnabled) els.btnClearHistory?.classList.remove('hidden');
}

function exportHtml() {
  const md = els.outputMd?.value?.trim();
  if (!md) {
    showStatus('No hay traducción para exportar.', 'error');
    return;
  }
  const title = state.downloadName?.replace(/\.md$/i, '') || 'traduccion';
  let bodyHtml = '';
  if (typeof marked !== 'undefined') {
    bodyHtml = marked.parse(md, { gfm: true, breaks: false });
  } else {
    bodyHtml = `<pre>${escapeHtml(md)}</pre>`;
  }
  const doc =
    `<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1">` +
    `<title>${escapeHtml(title)}</title><style>${EXPORT_CSS}</style></head>` +
    `<body>${bodyHtml}</body></html>`;
  const blob = new Blob([doc], { type: 'text/html;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${title}.html`;
  a.click();
  URL.revokeObjectURL(url);
  showStatus('HTML exportado.');
}

async function exportPdf() {
  const md = els.outputMd?.value?.trim();
  if (!md) {
    showStatus('No hay traducción para exportar.', 'error');
    return;
  }
  const title = state.downloadName?.replace(/\.md$/i, '') || 'traduccion';
  try {
    const res = await apiFetch('/api/export/pdf', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content: md, title }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(apiErrorMessage(err, 'Error al exportar PDF'));
    }
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${title}.pdf`;
    a.click();
    URL.revokeObjectURL(url);
    showStatus('PDF exportado.');
  } catch (err) {
    showStatus(err.message, 'error');
  }
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function buildDiffSegments(source, translated) {
  if (state.draftSegments.length) return state.draftSegments;
  if (source && translated) {
    return [{ index: 0, original: source, translated, doubtful: false }];
  }
  return [];
}

function renderDiff(source, translated) {
  const panel = els.diffPanel;
  if (!panel) return;
  const segments = buildDiffSegments(source, translated);
  if (typeof diff_match_patch === 'undefined') {
    panel.textContent = 'Diff no disponible (CDN no cargado).';
    return;
  }
  if (!segments.length) {
    setHtml(panel, '<p class="text-sm text-ink-muted p-2">Traduce primero para ver el diff.</p>');
    return;
  }
  const dmp = new diff_match_patch();
  setHtml(
    panel,
    segments
      .map((s) => {
        const diffs = dmp.diff_main(s.original || '', s.translated || '');
        dmp.diff_cleanupSemantic(diffs);
        const diffHtml = dmp.diff_prettyHtml(diffs);
        const doubtful = s.doubtful ? ' diff-segment-doubtful' : '';
        return `<div class="diff-segment${doubtful}"><p class="diff-segment-label">Segmento ${s.index}</p>${diffHtml}</div>`;
      })
      .join('')
  );
}

function switchPreviewTab(tab) {
  const isDiff = tab === 'diff';
  els.tabPreview?.classList.toggle('tab-btn-active', !isDiff);
  els.tabDiff?.classList.toggle('tab-btn-active', isDiff);
  els.tabPreview?.setAttribute('aria-selected', String(!isDiff));
  els.tabDiff?.setAttribute('aria-selected', String(isDiff));
  els.previewGrid?.classList.toggle('hidden', isDiff);
  els.diffPanel?.classList.toggle('hidden', !isDiff);
  if (isDiff) {
    renderDiff(state.sourceContent, els.outputMd?.value || '');
  }
}

function renderReviewSegments(segments) {
  if (!els.reviewSegments) return;
  if (!segments?.length) {
    setHtml(els.reviewSegments, '<p class="text-sm text-ink-muted">Sin segmentos traducibles.</p>');
    return;
  }
  setHtml(
    els.reviewSegments,
    segments
      .map(
        (s) => `
    <div class="review-segment${s.doubtful ? ' review-segment-doubtful' : ''}" data-segment-index="${s.index}">
      <p class="review-original text-xs text-ink-muted mb-1">${escapeHtml(s.original)}</p>
      <textarea class="review-edit w-full rounded-lg border border-teal-100 px-2 py-1 text-sm" rows="2">${escapeHtml(s.translated)}</textarea>
    </div>`
      )
      .join('')
  );
}

async function finalizeReview() {
  if (!state.sourceContent) return;
  hideStatus();
  setLoading(true, 'Confirmando…');
  const edits = {};
  els.reviewSegments?.querySelectorAll('[data-segment-index]').forEach((row) => {
    const idx = parseInt(row.getAttribute('data-segment-index'), 10);
    const textarea = row.querySelector('textarea');
    if (textarea) edits[idx] = textarea.value;
  });
  try {
    const res = await apiFetch('/api/translate/finalize', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content: state.sourceContent,
        segments: edits,
        source_lang: els.sourceLang.value,
        tone: getTone(),
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(apiErrorMessage(data, 'Error al confirmar revisión'));
    els.outputMd.value = data.content;
    state.draftSegments = Object.entries(edits).map(([index, translated]) => {
      const seg = state.draftSegments.find((s) => s.index === Number(index));
      return {
        index: Number(index),
        original: seg?.original || '',
        translated,
        doubtful: false,
      };
    });
    els.btnCopy.disabled = false;
    const primary = state.targetLangs[0];
    const blob = new Blob([data.content], { type: 'text/markdown;charset=utf-8' });
    state.downloadBlob = blob;
    state.downloadName = `traduccion.${primary}.md`;
    showDownloadButton();
    els.btnExportHtml?.classList.remove('hidden');
    els.btnExportPdf?.classList.remove('hidden');
    renderPreview(state.sourceContent, els.previewSource);
    renderPreview(data.content, els.previewResult);
    renderDiff(state.sourceContent, data.content);
    renderValidationPanel(data.validation);
    els.btnFinalizeReview?.classList.add('hidden');
    pushHistory({
      targetLang: primary,
      mode: 'editor-review',
      segments: data.segments_translated,
      chars: data.content.length,
    });
    showStatus('Revisión confirmada y lista para exportar.');
  } catch (err) {
    showStatus(err.message, 'error');
  } finally {
    setLoading(false);
  }
}

function onTranslateSuccess({ content, source, validation, segmentsTranslated, multiLang, skipRender }) {
  state.sourceContent = source || state.sourceContent;
  els.btnExportHtml?.classList.remove('hidden');
  els.btnExportPdf?.classList.remove('hidden');
  if (!skipRender) {
    renderPreview(source, els.previewSource);
    renderPreview(content, els.previewResult);
    renderDiff(source, content);
    renderValidationPanel(validation);
  }
  pushHistory({
    targetLang: state.targetLangs[0],
    mode: state.mode,
    segments: segmentsTranslated,
    chars: content?.length || 0,
  });
  if (!multiLang) {
    showStatus(`Listo — ${segmentsTranslated} segmentos traducidos.`);
  }
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
    const res = await apiFetch('/api/translate/estimate', {
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
    const res = await apiFetch('/api/translate/estimate', {
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

// ESTIMATE-01: estimación en tiempo real conforme el usuario escribe en el editor.
// Usa cuerpo JSON (no FormData) con el contenido actual del textarea.
async function fetchEstimateEditor() {
  if (!els.estimateEditor) return;
  const content = els.inputMd?.value?.trim();
  if (!content) {
    renderEstimateBlock(els.estimateEditor, null, null);
    return;
  }
  state.estimateEditorController?.abort();
  state.estimateEditorController = new AbortController();
  try {
    const res = await apiFetch('/api/translate/estimate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content,
        target_lang: state.targetLangs[0] || 'es',
        source_lang: els.sourceLang?.value || 'auto',
      }),
      signal: state.estimateEditorController.signal,
    });
    if (!res.ok) return;
    const data = await res.json();
    renderEstimateBlock(els.estimateEditor, null, data);
  } catch (err) {
    if (err.name !== 'AbortError') {
      renderEstimateBlock(els.estimateEditor, null, null);
    }
  }
}

const scheduleEstimateEditor = debounce(fetchEstimateEditor, 500);

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
  const res = await apiFetch(`/api/translate/batch/jobs/${jobId}/download`);
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(apiErrorMessage(err, 'No se pudo descargar el ZIP'));
  }
  state.downloadBlob = await res.blob();
  state.downloadName = 'traducciones.zip';
  showDownloadButton();
}

async function cancelBatchJob() {
  if (!state.batchJobId) return;
  if (!confirm('¿Cancelar la traducción en curso?')) return;
  try {
    await apiFetch(`/api/translate/batch/jobs/${state.batchJobId}`, {
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
    const res = await apiFetch('/api/glossary');
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
    const res = await apiFetch('/api/glossary', {
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
    const res = await apiFetch('/api/memory', { method: 'DELETE' });
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
  els.reviewSection?.classList.toggle('hidden', mode !== 'editor');
  els.btnDownload?.classList.add('hidden');
  els.btnExportHtml?.classList.add('hidden');
  els.btnExportPdf?.classList.add('hidden');
  clearResultLangTabs();
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
  clearResultLangTabs();
  state.sourceContent = content;
  const reviewMode =
    state.reviewMode && state.targetLangs.length === 1;
  try {
    if (reviewMode) {
      const res = await apiFetch('/api/translate/draft', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          content,
          target_lang: state.targetLangs[0],
          source_lang: els.sourceLang.value,
          tone: getTone(),
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(apiErrorMessage(data, 'Error de borrador'));
      state.draftSegments = data.segments || [];
      els.outputMd.value = data.content;
      renderReviewSegments(state.draftSegments);
      els.btnFinalizeReview?.classList.remove('hidden');
      els.btnCopy.disabled = false;
      const blob = new Blob([data.content], { type: 'text/markdown;charset=utf-8' });
      state.downloadBlob = blob;
      state.downloadName = `traduccion.${state.targetLangs[0]}.md`;
      showDownloadButton();
      els.btnExportHtml?.classList.remove('hidden');
      els.btnExportPdf?.classList.remove('hidden');
      renderPreview(content, els.previewSource);
      renderPreview(data.content, els.previewResult);
      renderDiff(content, data.content);
      renderValidationPanel(data.validation);
      showStatus(
        `Borrador — ${data.segments_translated} segmentos (${state.draftSegments.filter((s) => s.doubtful).length} dudosos).`
      );
      return;
    }

    const res = await apiFetch('/api/translate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content,
        target_lang: state.targetLangs[0],
        target_langs: state.targetLangs,
        source_lang: els.sourceLang.value,
        tone: getTone(),
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(apiErrorMessage(data, 'Error de traducción'));
    const primary = state.targetLangs[0];
    if (data.translations) {
      state.translationResults = data.translations;
      state.activeResultLang = primary;
      state.draftSegments = [];
      els.btnFinalizeReview?.classList.add('hidden');
      showTranslationForLang(primary);
      els.btnExportHtml?.classList.remove('hidden');
      const langCount = state.targetLangs.length;
      onTranslateSuccess({
        content: data.translations[primary].content,
        source: content,
        validation: data.translations[primary].validation,
        segmentsTranslated: data.translations[primary].segments_translated,
        multiLang: langCount > 1,
        skipRender: true,
      });
      if (langCount > 1) {
        showStatus(
          `Listo — ${langCount} idiomas traducidos (mostrando ${state.langNames[primary] || primary}).`
        );
      }
      // Notificar a la app macOS (si está disponible) que la traducción terminó.
      if (typeof window.__notifyTranslationDone === 'function') {
        const fname = langCount > 1 ? 'traducciones.zip' : `traduccion.${primary}.md`;
        const langs = state.targetLangs.map(l => state.langNames[l] || l).join(', ');
        window.__notifyTranslationDone(fname, langs);
      }
    } else {
      const result = data;
      state.draftSegments = [];
      els.outputMd.value = result.content;
      els.btnCopy.disabled = false;
      els.btnFinalizeReview?.classList.add('hidden');
      const blob = new Blob([result.content], { type: 'text/markdown;charset=utf-8' });
      state.downloadBlob = blob;
      state.downloadName = `traduccion.${primary}.md`;
      showDownloadButton();
      onTranslateSuccess({
        content: result.content,
        source: content,
        validation: result.validation,
        segmentsTranslated: result.segments_translated,
        multiLang: false,
      });
      // Notificar a la app macOS (si está disponible) que la traducción terminó.
      if (typeof window.__notifyTranslationDone === 'function') {
        const langs = state.langNames[primary] || primary;
        window.__notifyTranslationDone(state.downloadName, langs);
      }
      // Guardar archivo traducido en carpeta de salida macOS (si está disponible).
      if (typeof window.__saveTranslatedFile === 'function') {
        window.__saveTranslatedFile(state.downloadName, result.content);
      }
    }
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
    const res = await apiFetch('/api/translate/file', { method: 'POST', body: form });
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
      const src = await state.selectedFile.text();
      state.sourceContent = src;
      els.outputMd.value = text;
      els.btnCopy.disabled = false;
      renderPreview(src, els.previewSource);
      renderPreview(text, els.previewResult);
      renderDiff(src, text);
      const valHeader = res.headers.get('X-Validation-Report');
      if (valHeader) {
        try {
          renderValidationPanel(JSON.parse(valHeader));
        } catch {
          renderValidationPanel(null);
        }
      }
      showStatus(`Archivo traducido: ${state.downloadName}`);
      pushHistory({
        targetLang: state.targetLangs[0],
        mode: 'file',
        segments: 0,
        chars: text.length,
      });
      // Guardar archivo traducido en carpeta de salida macOS (si está disponible).
      if (typeof window.__saveTranslatedFile === 'function') {
        window.__saveTranslatedFile(state.downloadName, text);
      }
    }
    showDownloadButton();
    if (!contentType.includes('zip')) {
      els.btnExportHtml?.classList.remove('hidden');
      els.btnExportPdf?.classList.remove('hidden');
    }
    // Notificar a la app macOS (si está disponible) que la traducción terminó.
    if (typeof window.__notifyTranslationDone === 'function') {
      const langs = state.targetLangs.map(l => state.langNames[l] || l).join(', ');
      window.__notifyTranslationDone(state.downloadName, langs);
    }
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
    const res = await apiFetch('/api/translate/batch/jobs', {
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
        authEventSourceUrl(`/api/translate/batch/jobs/${jobId}/events`)
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
  // En la app macOS (WKWebView), blob: URLs no se pueden navegar para descarga.
  // Enviamos el archivo codificado en base64 al puente nativo nativeDownload,
  // que lo decodifica y abre NSSavePanel vía OutputManager.
  if (window.webkit?.messageHandlers?.nativeDownload) {
    const reader = new FileReader();
    reader.onload = (e) => {
      // e.target.result: "data:<mime>;base64,<datos>" → extraer solo los datos
      const base64 = e.target.result.split(',')[1];
      window.webkit.messageHandlers.nativeDownload.postMessage({
        filename: state.downloadName || 'descarga',
        base64,
        mimeType: state.downloadBlob.type || 'application/octet-stream',
      });
    };
    reader.readAsDataURL(state.downloadBlob);
    return;
  }
  // Navegador estándar: descarga vía blob URL
  const url = URL.createObjectURL(state.downloadBlob);
  const a = document.createElement('a');
  a.href = url;
  a.download = state.downloadName;
  a.click();
  URL.revokeObjectURL(url);
}

/// Muestra el botón de descarga y actualiza su etiqueta según el tipo de archivo.
/// Debe llamarse DESPUÉS de haber establecido state.downloadName.
function showDownloadButton() {
  if (!els.btnDownload) return;
  els.btnDownload.classList.remove('hidden');
  if (els.btnDownloadLabel) {
    els.btnDownloadLabel.textContent = (state.downloadName || '').endsWith('.zip')
      ? 'Descargar ZIP'
      : 'Descargar .md';
  }
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
els.btnExportHtml?.addEventListener('click', exportHtml);
els.btnExportPdf?.addEventListener('click', exportPdf);
els.btnFinalizeReview?.addEventListener('click', finalizeReview);
els.tabPreview?.addEventListener('click', () => switchPreviewTab('preview'));
els.tabDiff?.addEventListener('click', () => switchPreviewTab('diff'));
els.reviewModeToggle?.addEventListener('change', () => {
  state.reviewMode = Boolean(els.reviewModeToggle?.checked);
});
els.historyEnabled?.addEventListener('change', () => {
  state.historyEnabled = Boolean(els.historyEnabled?.checked);
  localStorage.setItem('md-translate-history-enabled', state.historyEnabled ? '1' : '0');
  if (state.historyEnabled) {
    els.btnClearHistory?.classList.remove('hidden');
  } else {
    els.btnClearHistory?.classList.add('hidden');
  }
});
els.btnClearHistory?.addEventListener('click', () => {
  localStorage.removeItem(HISTORY_KEY);
  els.btnClearHistory?.classList.add('hidden');
  showStatus('Historial local borrado.');
});

els.apiTokenToggle?.addEventListener('click', () => {
  const expanded = els.apiTokenPanel?.classList.toggle('hidden');
  const isOpen = !expanded;
  els.apiTokenToggle.setAttribute('aria-expanded', String(isOpen));
  els.apiTokenChevron?.classList.toggle('expanded', isOpen);
});

els.btnSaveApiToken?.addEventListener('click', () => {
  setApiToken(els.apiTokenInput?.value || '');
  showStatus('Token API guardado en este navegador.');
});

els.btnClearApiToken?.addEventListener('click', () => {
  setApiToken('');
  if (els.apiTokenInput) els.apiTokenInput.value = '';
  showStatus('Token API borrado.');
});

function initApiTokenField() {
  if (els.apiTokenInput) els.apiTokenInput.value = getApiToken();
}

// ESTIMATE-01: actualizar estimación del editor al cambiar idioma origen/destino
els.inputMd?.addEventListener('input', scheduleEstimateEditor);

els.sourceLang.addEventListener('change', () => {
  if (state.glossary.loaded) loadGlossary();
  scheduleEstimateBatch();
  scheduleEstimateFile();
  scheduleEstimateEditor();  // ESTIMATE-01
});
els.targetLang.addEventListener('change', () => {
  const code = els.targetLang.value;
  if (code) addTargetLang(code);
  els.targetLang.selectedIndex = 0;
  scheduleEstimateEditor();  // ESTIMATE-01
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
initHistory();
initApiTokenField();
if (state.mode === 'editor') {
  els.reviewSection?.classList.remove('hidden');
}
