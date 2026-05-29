# 04-02 Summary

**Plan:** deployment.py — CORS, límites upload, TTL output/, API_TOKEN

## Entregado

- `src/deployment.py` — get_cors_origins, check_upload_limits, sweep_output_dir, verify_api_token
- `src/main.py` — CORS restrictivo, startup sweep + tarea periódica, límites en uploads, Depends token
- `.env.example` — variables SEC documentadas
- `tests/test_deployment.py`, tests upload/CORS en `test_api.py`

## Verificación

`pytest tests/test_deployment.py tests/test_api.py -q -k "upload or cors"` — PASS
