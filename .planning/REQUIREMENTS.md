# Requirements: v2.1 Reproducible Dependencies

## v1 Requirements

### Lockfile

- [ ] **LOCK-01**: El proyecto incluye `uv.lock` generado desde `pyproject.toml` con versiones exactas de todas las dependencias (directas e indirectas), commiteado en git
- [ ] **LOCK-02**: El desarrollador puede reproducir el entorno exacto con `uv sync` sin argumentos adicionales
- [ ] **LOCK-03**: Existe un flujo documentado para actualizar el lockfile al añadir/cambiar dependencias (`uv add`, `uv lock --upgrade`)

### Documentación

- [ ] **LOCK-04**: README actualizado con instrucciones de instalación vía `uv` (recomendado) y `pip` clásico (alternativa sin cambios de toolchain)

### Docker

- [ ] **LOCK-05**: `Dockerfile` y `docker-compose.yml` actualizados para instalar dependencias vía `uv sync --frozen` usando el lockfile

## Future Requirements

*(ninguno identificado — scope completo en v2.1)*

## Out of Scope

- Migración de build backend (setuptools → uv build): invasivo, sin beneficio inmediato
- poetry.lock / pip-compile: sustituidos por uv
- Lockfile para dependencias opcionales de test por separado: innecesario con uv groups

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| LOCK-01 | Phase 8 | Pending |
| LOCK-02 | Phase 8 | Pending |
| LOCK-03 | Phase 8 | Pending |
| LOCK-04 | Phase 8 | Pending |
| LOCK-05 | Phase 8 | Pending |
