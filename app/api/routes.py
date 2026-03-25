from __future__ import annotations
from pathlib import Path

from fastapi import APIRouter, HTTPException, UploadFile
from fastapi.responses import PlainTextResponse, Response

from app.api.schemas import LayerInfo, LayerUpdateRequest, UploadResponse
from app.dwg.converter import ConversionError, convert_dwg_to_dxf, convert_pdf_to_dxf
from app.dwg.layer_mapping import LayerMapper
from app.dwg.parser import parse_dxf
from app.dwg.pdf_scanner import ScannerNotAvailable, is_scanner_available, parse_scanned_pdf
from app.geometry.furniture import map_furniture_to_components
from app.geometry.openings import associate_openings_with_walls
from app.geometry.walls import detect_wall_thickness, merge_collinear_walls
from app.preview.svg_renderer import render_svg
from app.sketchup.generator import generate_ruby_script
from app.storage.file_manager import (
    cleanup_session,
    create_session,
    get_plan,
    get_session_dir,
    save_uploaded_file,
    store_plan,
)

router = APIRouter(prefix="/api")

ALLOWED_EXTENSIONS = {".dwg", ".dxf", ".pdf"}


def _get_dxf_path(session_id: str, file_path: Path) -> Path:
    """Convert uploaded file to DXF if needed, return DXF path."""
    suffix = file_path.suffix.lower()
    if suffix == ".dxf":
        return file_path
    output_dir = get_session_dir(session_id)
    if suffix == ".dwg":
        return convert_dwg_to_dxf(file_path, output_dir)
    if suffix == ".pdf":
        return convert_pdf_to_dxf(file_path, output_dir)
    raise HTTPException(400, f"Unsupported file type: {suffix}")


@router.post("/upload", response_model=UploadResponse)
async def upload_file(file: UploadFile):
    if not file.filename:
        raise HTTPException(400, "No filename provided")

    suffix = Path(file.filename).suffix.lower()
    if suffix not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, f"Unsupported file type. Allowed: {', '.join(ALLOWED_EXTENSIONS)}")

    session_id = create_session()

    try:
        content = await file.read()
        file_path = save_uploaded_file(session_id, file.filename, content)

        # Try CAD conversion first; for PDFs, fall back to scanned parser
        suffix = file_path.suffix.lower()
        plan = None
        if suffix == ".pdf":
            # Try ODA CAD-PDF conversion first
            cad_conversion_failed = False
            try:
                dxf_path = _get_dxf_path(session_id, file_path)
                plan = parse_dxf(dxf_path)
            except (ConversionError, OSError, ValueError, RuntimeError):
                cad_conversion_failed = True

            # Fall back to scanned PDF parser
            if cad_conversion_failed or (plan and not plan.walls):
                if is_scanner_available():
                    plan = parse_scanned_pdf(file_path)
                elif cad_conversion_failed:
                    cleanup_session(session_id)
                    raise HTTPException(
                        422,
                        "PDF is not a CAD-exported PDF and scanned PDF support "
                        "requires pymupdf and opencv-python. "
                        "Install with: pip install pymupdf opencv-python numpy"
                    )
        else:
            dxf_path = _get_dxf_path(session_id, file_path)
            plan = parse_dxf(dxf_path)

        # Process geometry
        plan.walls = merge_collinear_walls(plan.walls)
        plan.walls = detect_wall_thickness(plan.walls)
        plan.openings = associate_openings_with_walls(plan.openings, plan.walls)
        plan.furniture = map_furniture_to_components(plan.furniture)
        plan.compute_bounds()

        store_plan(session_id, plan)

        # Get layer classifications
        mapper = LayerMapper()
        all_layers = set()
        for w in plan.walls:
            all_layers.add(w.layer)
        for o in plan.openings:
            all_layers.add(o.layer)
        for f in plan.furniture:
            all_layers.add(f.layer)
        layer_types = mapper.classify_layers(list(all_layers))

        return UploadResponse(
            session_id=session_id,
            filename=file.filename,
            wall_count=len(plan.walls),
            opening_count=len(plan.openings),
            furniture_count=len(plan.furniture),
            units=plan.units,
            layers=layer_types,
        )
    except HTTPException:
        cleanup_session(session_id)
        raise
    except ConversionError as e:
        cleanup_session(session_id)
        raise HTTPException(422, str(e))
    except Exception as e:
        cleanup_session(session_id)
        raise HTTPException(500, f"Failed to process file: {e}")


@router.get("/preview/{session_id}")
async def get_preview(session_id: str):
    plan = get_plan(session_id)
    if not plan:
        raise HTTPException(404, "Session not found")
    svg = render_svg(plan)
    return Response(content=svg, media_type="image/svg+xml")


@router.get("/download/{session_id}")
async def download_script(session_id: str):
    plan = get_plan(session_id)
    if not plan:
        raise HTTPException(404, "Session not found")
    script = generate_ruby_script(plan)
    filename = Path(plan.source_filename).stem + "_sketchup.rb"
    return PlainTextResponse(
        content=script,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/layers/{session_id}", response_model=LayerInfo)
async def get_layers(session_id: str):
    plan = get_plan(session_id)
    if not plan:
        raise HTTPException(404, "Session not found")
    mapper = LayerMapper()
    all_layers = set()
    for w in plan.walls:
        all_layers.add(w.layer)
    for o in plan.openings:
        all_layers.add(o.layer)
    for f in plan.furniture:
        all_layers.add(f.layer)
    return LayerInfo(layers=mapper.classify_layers(list(all_layers)))


@router.post("/layers/{session_id}/update")
async def update_layers(session_id: str, request: LayerUpdateRequest):
    plan = get_plan(session_id)
    if not plan:
        raise HTTPException(404, "Session not found")

    # Re-parse with custom mapping
    from app.storage.file_manager import get_file_path
    file_path = get_file_path(session_id)
    if not file_path:
        raise HTTPException(404, "Original file not found")

    dxf_path = _get_dxf_path(session_id, file_path)
    plan = parse_dxf(dxf_path, custom_layer_mapping=request.mapping)
    plan.walls = merge_collinear_walls(plan.walls)
    plan.walls = detect_wall_thickness(plan.walls)
    plan.openings = associate_openings_with_walls(plan.openings, plan.walls)
    plan.furniture = map_furniture_to_components(plan.furniture)
    plan.compute_bounds()

    store_plan(session_id, plan)
    return {"status": "ok", "wall_count": len(plan.walls), "opening_count": len(plan.openings)}


@router.delete("/session/{session_id}")
async def delete_session(session_id: str):
    cleanup_session(session_id)
    return {"status": "deleted"}
