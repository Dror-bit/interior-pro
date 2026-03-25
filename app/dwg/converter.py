from __future__ import annotations
import shutil
import subprocess
from pathlib import Path

from app.config import settings


class ConversionError(Exception):
    pass


def _find_oda_converter() -> str | None:
    if settings.oda_converter_path:
        path = Path(settings.oda_converter_path)
        if path.exists():
            return str(path)
    # Try common install locations
    candidates = [
        r"C:\Program Files\ODA\ODAFileConverter\ODAFileConverter.exe",
        r"C:\Program Files (x86)\ODA\ODAFileConverter\ODAFileConverter.exe",
        "/usr/bin/ODAFileConverter",
        "/usr/local/bin/ODAFileConverter",
    ]
    for c in candidates:
        if Path(c).exists():
            return c
    # Check if it's on PATH
    found = shutil.which("ODAFileConverter")
    return found


def is_oda_available() -> bool:
    return _find_oda_converter() is not None


def convert_dwg_to_dxf(dwg_path: Path, output_dir: Path) -> Path:
    converter = _find_oda_converter()
    if not converter:
        raise ConversionError(
            "ODA File Converter not found. Install it from "
            "https://www.opendesign.com/guestfiles/oda_file_converter "
            "or set ODA_CONVERTER_PATH in .env"
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    input_dir = dwg_path.parent
    input_name = dwg_path.stem

    # ODA converter args: input_dir output_dir version type recurse audit
    # "ACAD2018" = AutoCAD 2018 DXF format, "DXF" = output type, "0" = no recurse, "1" = audit
    try:
        result = subprocess.run(
            [
                converter,
                str(input_dir),
                str(output_dir),
                "ACAD2018",
                "DXF",
                "0",
                "1",
                str(dwg_path.name),
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        raise ConversionError("DWG conversion timed out (120s limit)")

    output_dxf = output_dir / f"{input_name}.dxf"
    if not output_dxf.exists():
        raise ConversionError(
            f"Conversion failed. ODA output: {result.stdout} {result.stderr}"
        )

    return output_dxf


def convert_pdf_to_dxf(pdf_path: Path, output_dir: Path) -> Path:
    """Convert a CAD-exported PDF to DXF using ODA File Converter."""
    converter = _find_oda_converter()
    if not converter:
        raise ConversionError(
            "ODA File Converter not found. Required for PDF-to-DXF conversion."
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    input_dir = pdf_path.parent
    input_name = pdf_path.stem

    try:
        result = subprocess.run(
            [
                converter,
                str(input_dir),
                str(output_dir),
                "ACAD2018",
                "DXF",
                "0",
                "1",
                str(pdf_path.name),
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        raise ConversionError("PDF conversion timed out (120s limit)")

    output_dxf = output_dir / f"{input_name}.dxf"
    if not output_dxf.exists():
        raise ConversionError(
            f"PDF conversion failed (may not be a CAD-exported PDF). "
            f"ODA output: {result.stdout} {result.stderr}"
        )

    return output_dxf
