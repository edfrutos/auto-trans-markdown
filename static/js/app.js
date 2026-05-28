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
};

const $ = (sel) => document.querySelector(sel);

/** Evita crash si el HTML en caché no incluye nodos de fases nuevas. */
function setHtml(el, html) {
  if (el) el.innerHTML = html;
}

const els = {
  sourceLang: $('#source-lang'),
  targetLang: $('#target-lang'),
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
  const tgt = els.targetLang.value;
  return `${src}-${tgt}`;
}

function flattenGlossary(data) {
  const entries = [];
  for (const term of data.do_not_translate || []) {
    entries.push({ term, translation: '', dnt: true });
  }
  const pk = pairKey();
  const pairs = data.pairs?.[pk] || data.pairs?.[`auto-${els.targetLang.value}`] || {};
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
    setHtml(els.targetLang, '');
    setHtml(els.sourceLang, '<option value="auto">Detectar automáticamente</option>');
    let defaultSet = false;
    for (const { code, name } of langs) {
      if (code === 'auto') continue;
      const optTarget = document.createElement('option');
      optTarget.value = code;
      optTarget.textContent = name;
      if (code === 'es') {
        optTarget.selected = true;
        defaultSet = true;
      }
      els.targetLang.appendChild(optTarget);

      const optSource = document.createElement('option');
      optSource.value = code;
      optSource.textContent = name;
      els.sourceLang.appendChild(optSource);
    }
    if (!defaultSet && els.targetLang.options.length > 0) {
      els.targetLang.options[0].selected = true;
    }
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
        target_lang: els.targetLang.value,
        source_lang: els.sourceLang.value,
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(apiErrorMessage(data, 'Error de traducción'));
    els.outputMd.value = data.content;
    els.btnCopy.disabled = false;
    const blob = new Blob([data.content], { type: 'text/markdown;charset=utf-8' });
    state.downloadBlob = blob;
    state.downloadName = `traduccion.${els.targetLang.value}.md`;
    els.btnDownload.classList.remove('hidden');
    showStatus(`Listo — ${data.segments_translated} segmentos traducidos.`);
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
  form.append('target_lang', els.targetLang.value);
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
    state.downloadName = match ? match[1] : `traduccion.${els.targetLang.value}.md`;
    els.outputMd.value = await blob.text();
    els.btnCopy.disabled = false;
    els.btnDownload.classList.remove('hidden');
    showStatus(`Archivo traducido: ${state.downloadName}`);
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
  setLoading(true, `Traduciendo ${state.batchFiles.length} archivos…`);
  const form = new FormData();
  state.batchFiles.forEach((f) => form.append('files', f));
  form.append('target_lang', els.targetLang.value);
  form.append('source_lang', els.sourceLang.value);
  try {
    const res = await fetch('/api/translate/batch', { method: 'POST', body: form });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(apiErrorMessage(err, 'Error en traducción por lote'));
    }
    const blob = await res.blob();
    state.downloadBlob = blob;
    state.downloadName = 'traducciones.zip';
    els.btnDownload.classList.remove('hidden');
    showStatus(`${state.batchFiles.length} archivos traducidos — descarga el ZIP.`);
  } catch (err) {
    showStatus(err.message, 'error');
  } finally {
    setLoading(false);
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
els.btnSample?.addEventListener('click', () => { els.inputMd.value = SAMPLE_MD; });
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

els.btnAddGlossary?.addEventListener('click', () => {
  state.glossary.entries.push({ term: '', translation: '', dnt: false });
  state.glossary.dirty = true;
  renderGlossaryTable();
});

els.btnSaveGlossary?.addEventListener('click', saveGlossary);
els.btnClearMemory?.addEventListener('click', clearMemory);

els.sourceLang.addEventListener('change', () => {
  if (state.glossary.loaded) loadGlossary();
});
els.targetLang.addEventListener('change', () => {
  if (state.glossary.loaded) loadGlossary();
});

if (els.dropZone && els.fileInput) {
  setupDropZone(els.dropZone, els.fileInput, (files) => {
    const f = files[0];
    if (!f) return;
    state.selectedFile = f;
    if (els.fileName) {
      els.fileName.textContent = f.name;
      els.fileName.classList.remove('hidden');
    }
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
  });
}

loadLanguages();
initTheme();
