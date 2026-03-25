from __future__ import annotations
import shutil
import uuid
from pathlib import Path

from app.config import settings
from app.dwg.elements import FloorPlan

# In-memory store for parsed floor plans (keyed by UUID)
_plans: dict[str, FloorPlan] = {}
_file_paths: dict[str, Path] = {}


def get_upload_dir() -> Path:
    d = settings.upload_dir
    d.mkdir(parents=True, exist_ok=True)
    return d


def create_session() -> str:
    session_id = str(uuid.uuid4())
    session_dir = get_upload_dir() / session_id
    session_dir.mkdir(parents=True, exist_ok=True)
    return session_id


def get_session_dir(session_id: str) -> Path:
    return get_upload_dir() / session_id


def save_uploaded_file(session_id: str, filename: str, content: bytes) -> Path:
    session_dir = get_session_dir(session_id)
    session_dir.mkdir(parents=True, exist_ok=True)
    file_path = session_dir / filename
    file_path.write_bytes(content)
    _file_paths[session_id] = file_path
    return file_path


def store_plan(session_id: str, plan: FloorPlan) -> None:
    _plans[session_id] = plan


def get_plan(session_id: str) -> FloorPlan | None:
    return _plans.get(session_id)


def get_file_path(session_id: str) -> Path | None:
    return _file_paths.get(session_id)


def cleanup_session(session_id: str) -> None:
    _plans.pop(session_id, None)
    _file_paths.pop(session_id, None)
    session_dir = get_session_dir(session_id)
    if session_dir.exists():
        shutil.rmtree(session_dir)
