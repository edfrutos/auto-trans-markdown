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
};

const $ = (sel) => document.querySelector(sel);

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
};

const tabs = [
  { tab: $('#tab-editor'), panel: $('#panel-editor'), mode: 'editor' },
  { tab: $('#tab-file'), panel: $('#panel-file'), mode: 'file' },
  { tab: $('#tab-batch'), panel: $('#panel-batch'), mode: 'batch' },
];

function showStatus(message, type = 'success') {
  els.status.textContent = message;
  els.status.className = `mt-4 rounded-xl px-4 py-3 text-sm ${type}`;
  els.status.classList.remove('hidden');
}

function hideStatus() {
  els.status.classList.add('hidden');
}

function setLoading(loading, text = 'Traduciendo…') {
  state.loading = loading;
  els.btnTranslate.disabled = loading;
  els.btnTranslateLabel.textContent = loading ? text : 'Traducir';
  if (loading) {
    els.progressWrap.classList.remove('hidden');
    els.progressBar.style.width = '30%';
    els.progressText.textContent = 'Procesando con IA…';
  } else {
    els.progressBar.style.width = '100%';
    setTimeout(() => {
      els.progressWrap.classList.add('hidden');
      els.progressBar.style.width = '0%';
    }, 400);
  }
}

function apiErrorMessage(err, fallback) {
  if (!err) return fallback;
  if (typeof err.detail === 'string') return err.detail;
  if (Array.isArray(err.detail)) {
    return err.detail.map((d) => d.msg || String(d)).join('; ');
  }
  return fallback;
}

async function loadLanguages() {
  try {
    const res = await fetch('/api/languages');
    const langs = await res.json();
    els.targetLang.innerHTML = '';
    els.sourceLang.innerHTML = '<option value="auto">Detectar automáticamente</option>';
    for (const { code, name } of langs) {
      if (code === 'auto') continue;
      const optTarget = document.createElement('option');
      optTarget.value = code;
      optTarget.textContent = name;
      if (code === 'es') optTarget.selected = true;
      els.targetLang.appendChild(optTarget);

      const optSource = document.createElement('option');
      optSource.value = code;
      optSource.textContent = name;
      els.sourceLang.appendChild(optSource);
    }
  } catch {
    /* defaults en HTML */
  }
}

function switchTab(mode) {
  state.mode = mode;
  tabs.forEach(({ tab, panel, mode: m }) => {
    const active = m === mode;
    tab.setAttribute('aria-selected', String(active));
    tab.classList.toggle('tab-btn-active', active);
    panel.classList.toggle('hidden', !active);
  });
  els.btnDownload.classList.add('hidden');
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
  els.iconSun.classList.toggle('hidden', !dark);
  els.iconMoon.classList.toggle('hidden', dark);
}

function toggleTheme() {
  const isDark = document.documentElement.classList.toggle('dark');
  localStorage.setItem('theme', isDark ? 'dark' : 'light');
  els.iconSun.classList.toggle('hidden', !isDark);
  els.iconMoon.classList.toggle('hidden', isDark);
}

// Event listeners
tabs.forEach(({ tab, mode }) => tab.addEventListener('click', () => switchTab(mode)));
els.btnTranslate.addEventListener('click', handleTranslate);
els.btnDownload.addEventListener('click', downloadResult);
els.btnSample.addEventListener('click', () => { els.inputMd.value = SAMPLE_MD; });
els.btnCopy.addEventListener('click', async () => {
  await navigator.clipboard.writeText(els.outputMd.value);
  showStatus('Copiado al portapapeles.');
});
els.themeToggle.addEventListener('click', toggleTheme);

setupDropZone(els.dropZone, els.fileInput, (files) => {
  const f = files[0];
  if (!f) return;
  state.selectedFile = f;
  els.fileName.textContent = f.name;
  els.fileName.classList.remove('hidden');
});

setupDropZone(els.dropZoneBatch, els.batchInput, (files) => {
  state.batchFiles = Array.from(files).filter((f) =>
    /\.(md|markdown|mdx)$/i.test(f.name)
  );
  els.batchList.innerHTML = state.batchFiles
    .map((f) => `<li>${f.name}</li>`)
    .join('');
  els.batchList.classList.toggle('hidden', !state.batchFiles.length);
});

loadLanguages();
initTheme();
