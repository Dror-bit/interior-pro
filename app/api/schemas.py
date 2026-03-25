from __future__ import annotations
from pydantic import BaseModel


class UploadResponse(BaseModel):
    session_id: str
    filename: str
    wall_count: int
    opening_count: int
    furniture_count: int
    units: str
    layers: dict[str, str | None]


class LayerInfo(BaseModel):
    layers: dict[str, str | None]


class LayerUpdateRequest(BaseModel):
    mapping: dict[str, str]


class ErrorResponse(BaseModel):
    detail: str
