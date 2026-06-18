"""Tests de integración end-to-end (Phase 32 — E2E-01..04).

Arrancan un servidor uvicorn real en un puerto libre y verifican los endpoints
principales más el flujo completo de lote asíncrono.

El mock se activa mediante la variable de entorno E2E_MOCK_TRANSLATE=1, que
translate_segments detecta internamente y devuelve textos prefijados con [MOCK]
sin llamar a la API real (ver src/translator.py).

Ejecutar con:
    make e2e
    # o directamente:
    pytest tests/test_e2e.py -v
"""

from __future__ import annotations

import io
import json
import os
import socket
import subprocess
import sys
import time
import zipfile

import pytest
import requests

# ---------------------------------------------------------------------------
# E2E-01 — Fixture live_server
# E2E-02 — Mock activado con E2E_MOCK_TRANSLATE=1 (guarda en translator.py)
# ---------------------------------------------------------------------------


def _find_free_port() -> int:
    """Pide al kernel un puerto TCP libre en loopback y lo libera."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="module")
def live_server(tmp_path_factory):
    """Arranca uvicorn src.main:app en un puerto libre con translate_segments mockeado.

    E2E_MOCK_TRANSLATE=1 activa la guarda dentro de translate_segments que devuelve
    textos [MOCK]-prefijados sin llamar a la API (E2E-02).
    OUTPUT_DIR y DATA_DIR apuntan a directorios temporales para no contaminar el
    árbol del proyecto (importante en sandboxes con permisos limitados).
    """
    port = _find_free_port()
    tmp = tmp_path_factory.mktemp("e2e_server")
    (tmp / "output").mkdir()
    (tmp / "data").mkdir()
    log_file = tmp / "server.log"
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    env = os.environ.copy()
    env["PORT"] = str(port)
    env["HOST"] = "127.0.0.1"
    env["TRANSLATION_PROVIDER"] = "openai"
    env["OPENAI_API_KEY"] = "sk-e2e-mock-key"   # clave falsa — mock no la usa
    env["OPENAI_MODEL"] = "gpt-4o-mini"
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env["PYTHONUNBUFFERED"] = "1"
    # E2E-02: activa el mock dentro de translate_segments (src/translator.py)
    env["E2E_MOCK_TRANSLATE"] = "1"
    # Directorios aislados — evita tocar output/ y data/ del proyecto real
    env["OUTPUT_DIR"] = str(tmp / "output")
    env["DATA_DIR"] = str(tmp / "data")
    # TM aislada
    env["TM_DB_PATH"] = str(tmp / "data" / "e2e_tm.db")

    python = sys.executable
    with open(log_file, "w") as log_fh:
        proc = subprocess.Popen(
            [
                python, "-m", "uvicorn", "src.main:app",
                "--port", str(port),
                "--host", "127.0.0.1",
                "--no-access-log",
                "--log-level", "warning",
            ],
            cwd=project_root,
            env=env,
            stdout=log_fh,
            stderr=subprocess.STDOUT,
        )

    # Health check: esperar hasta 15 s
    base_url = f"http://127.0.0.1:{port}"
    deadline = time.monotonic() + 15
    ready = False
    while time.monotonic() < deadline:
        try:
            r = requests.get(f"{base_url}/api/languages", timeout=1)
            if r.status_code == 200:
                ready = True
                break
        except requests.ConnectionError:
            pass
        time.sleep(0.3)

    if not ready:
        proc.kill()
        proc.wait()
        raise RuntimeError(
            f"El servidor no respondió en 15 s. Log:\n{log_file.read_text()}"
        )

    yield base_url

    # Teardown graceful
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


# ---------------------------------------------------------------------------
# E2E-03 — Tests de los endpoints principales
# ---------------------------------------------------------------------------

SAMPLE_MD = "# Hola mundo\n\nEste es un párrafo de prueba para el test E2E.\n"


class TestTranslateText:
    """POST /api/translate — texto plano."""

    def test_status_200(self, live_server):
        r = requests.post(
            f"{live_server}/api/translate",
            json={"content": SAMPLE_MD, "target_lang": "en"},
            timeout=10,
        )
        assert r.status_code == 200, r.text

    def test_response_has_translated_content(self, live_server):
        r = requests.post(
            f"{live_server}/api/translate",
            json={"content": SAMPLE_MD, "target_lang": "en"},
            timeout=10,
        )
        body = r.json()
        # La respuesta usa el campo "content" (no "translated")
        assert "content" in body
        assert len(body["content"]) > 0

    def test_mock_prefix_present(self, live_server):
        """Verifica que el mock está activo y el texto traducido lleva [MOCK]."""
        r = requests.post(
            f"{live_server}/api/translate",
            json={"content": SAMPLE_MD, "target_lang": "en"},
            timeout=10,
        )
        body = r.json()
        assert "[MOCK]" in body["content"], (
            "El mock de translate_segments no está activo. "
            f"content = {body.get('content', '')[:200]}"
        )

    def test_markdown_structure_preserved(self, live_server):
        """Bloques de código se preservan sin traducir."""
        md = "# Título\n\n```python\nprint('hello')\n```\n\nTexto traducible.\n"
        r = requests.post(
            f"{live_server}/api/translate",
            json={"content": md, "target_lang": "fr"},
            timeout=10,
        )
        body = r.json()
        assert "```python" in body["content"]
        assert "print('hello')" in body["content"]

    def test_unsupported_lang_returns_400(self, live_server):
        r = requests.post(
            f"{live_server}/api/translate",
            json={"content": SAMPLE_MD, "target_lang": "xx-invalid"},
            timeout=10,
        )
        assert r.status_code == 400

    def test_empty_content_returns_400(self, live_server):
        r = requests.post(
            f"{live_server}/api/translate",
            json={"content": "", "target_lang": "en"},
            timeout=10,
        )
        assert r.status_code == 400


class TestTranslateFile:
    """POST /api/translate/file — subida de archivo .md."""

    def test_status_200(self, live_server):
        r = requests.post(
            f"{live_server}/api/translate/file",
            files={"file": ("doc.md", SAMPLE_MD.encode(), "text/markdown")},
            data={"target_lang": "en"},
            timeout=10,
        )
        assert r.status_code == 200, r.text

    def test_translated_content_returned(self, live_server):
        r = requests.post(
            f"{live_server}/api/translate/file",
            files={"file": ("test.md", SAMPLE_MD.encode(), "text/markdown")},
            data={"target_lang": "de"},
            timeout=10,
        )
        assert r.status_code == 200
        body_text = r.content.decode("utf-8")
        assert "[MOCK]" in body_text

    def test_non_md_extension_returns_400(self, live_server):
        r = requests.post(
            f"{live_server}/api/translate/file",
            files={"file": ("doc.txt", b"hello", "text/plain")},
            data={"target_lang": "en"},
            timeout=10,
        )
        assert r.status_code == 400


class TestEstimate:
    """POST /api/translate/estimate — estimación de coste."""

    def test_status_200(self, live_server):
        r = requests.post(
            f"{live_server}/api/translate/estimate",
            json={"content": SAMPLE_MD, "target_lang": "en"},
            timeout=10,
        )
        assert r.status_code == 200, r.text

    def test_response_fields(self, live_server):
        r = requests.post(
            f"{live_server}/api/translate/estimate",
            json={"content": SAMPLE_MD, "target_lang": "en"},
            timeout=10,
        )
        body = r.json()
        for field in ("segments", "characters", "estimated_cost_usd", "provider", "model"):
            assert field in body, f"Campo '{field}' ausente en la respuesta"

    def test_segments_count_positive(self, live_server):
        # Usamos contenido diferente al SAMPLE_MD para evitar que la TM
        # del servidor ya tenga estos segmentos cacheados (lo que devolvería segments=0).
        unique_md = "# Test de estimación\n\nContenido exclusivo para el test de segmentos.\n"
        r = requests.post(
            f"{live_server}/api/translate/estimate",
            json={"content": unique_md, "target_lang": "fr"},
            timeout=10,
        )
        body = r.json()
        assert body["segments"] >= 1

    def test_empty_content_returns_400(self, live_server):
        r = requests.post(
            f"{live_server}/api/translate/estimate",
            json={"content": "", "target_lang": "en"},
            timeout=10,
        )
        assert r.status_code == 400


# ---------------------------------------------------------------------------
# E2E-04 — Flujo completo de lote asíncrono con SSE
# ---------------------------------------------------------------------------

def _make_batch_zip(files: dict[str, str]) -> bytes:
    """Crea un ZIP en memoria con los archivos .md dados."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, content in files.items():
            zf.writestr(name, content)
    return buf.getvalue()


class TestBatchJob:
    """Flujo completo: subir ZIP → consumir SSE → descargar ZIP resultado."""

    BATCH_FILES = {
        "doc1.md": "# Documento 1\n\nPrimer archivo de prueba.\n",
        "doc2.md": "# Documento 2\n\nSegundo archivo de prueba.\n",
        "doc3.md": "# Documento 3\n\nTercer archivo de prueba.\n",
    }

    def test_batch_full_flow(self, live_server):
        zip_bytes = _make_batch_zip(self.BATCH_FILES)

        # 1. Crear job de lote asíncrono con los 3 archivos .md
        r = requests.post(
            f"{live_server}/api/translate/batch/jobs",
            files=[
                ("files", (name, content.encode(), "text/markdown"))
                for name, content in self.BATCH_FILES.items()
            ],
            data={"target_lang": "en"},
            timeout=15,
        )
        assert r.status_code == 200, f"Batch job creation falló ({r.status_code}): {r.text}"
        body = r.json()
        assert "job_id" in body, f"Respuesta sin job_id: {body}"
        job_id = body["job_id"]

        # 2. Consumir SSE hasta recibir type=complete o type=error (timeout 25 s)
        final_event = None
        deadline = time.monotonic() + 25
        with requests.get(
            f"{live_server}/api/translate/batch/jobs/{job_id}/events",
            stream=True,
            timeout=25,
        ) as sse:
            assert sse.status_code == 200, f"SSE endpoint falló: {sse.status_code}"
            for raw_line in sse.iter_lines(decode_unicode=True):
                if time.monotonic() > deadline:
                    break
                if not raw_line or not raw_line.startswith("data:"):
                    continue
                try:
                    event = json.loads(raw_line[len("data:"):].strip())
                except json.JSONDecodeError:
                    continue
                event_type = event.get("type")
                if event_type in ("complete", "error"):
                    final_event = event
                    break

        assert final_event is not None, "No se recibió evento de finalización en el SSE"
        assert final_event.get("type") == "complete", (
            f"El job terminó con type={final_event.get('type')!r} (esperado 'complete'). "
            f"Evento: {final_event}"
        )

        # 3. Descargar el ZIP resultado
        r_zip = requests.get(
            f"{live_server}/api/translate/batch/jobs/{job_id}/download",
            timeout=10,
        )
        assert r_zip.status_code == 200, f"Descarga ZIP falló ({r_zip.status_code}): {r_zip.text}"

        # 4. Verificar que el ZIP contiene 3 archivos .md traducidos
        result_zip = zipfile.ZipFile(io.BytesIO(r_zip.content))
        md_files = [n for n in result_zip.namelist() if n.endswith(".md")]
        assert len(md_files) == 3, (
            f"ZIP resultado contiene {len(md_files)} archivos .md (esperado 3): "
            f"{result_zip.namelist()}"
        )

        # 5. Verificar que cada archivo lleva el prefijo [MOCK]
        for name in md_files:
            content = result_zip.read(name).decode("utf-8")
            assert "[MOCK]" in content, (
                f"El archivo '{name}' no contiene [MOCK]: {content[:200]}"
            )
