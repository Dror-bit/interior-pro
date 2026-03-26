from __future__ import annotations
import shutil
import subprocess
from pathlib import Path

from app.config import settings


class ConversionError(Exception):
    pass


# ---------------------------------------------------------------------------
# LibreDWG detection (free, open-source – preferred)
# ---------------------------------------------------------------------------

def _find_libredwg() -> str | None:
    """Find the LibreDWG dwg2dxf binary."""
    if settings.libredwg_path:
        path = Path(settings.libredwg_path)
        if path.exists():
            return str(path)

    # Try common install locations
    candidates = [
        # Windows – MSYS2 / manual install
        r"C:\msys64\mingw64\bin\dwg2dxf.exe",
        r"C:\Program Files\LibreDWG\dwg2dxf.exe",
        r"C:\Program Files (x86)\LibreDWG\dwg2dxf.exe",
        r"C:\LibreDWG\dwg2dxf.exe",
        # Linux / macOS
        "/usr/bin/dwg2dxf",
        "/usr/local/bin/dwg2dxf",
    ]
    for c in candidates:
        if Path(c).exists():
            return c

    # Check PATH
    found = shutil.which("dwg2dxf")
    return found


def is_libredwg_available() -> bool:
    return _find_libredwg() is not None


def convert_dwg_to_dxf_libredwg(dwg_path: Path, output_dir: Path) -> Path:
    """Convert DWG → DXF using LibreDWG's dwg2dxf tool."""
    converter = _find_libredwg()
    if not converter:
        raise ConversionError("LibreDWG dwg2dxf not found")

    output_dir.mkdir(parents=True, exist_ok=True)
    output_dxf = output_dir / f"{dwg_path.stem}.dxf"

    try:
        result = subprocess.run(
            [converter, "-o", str(output_dxf), str(dwg_path)],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        raise ConversionError("DWG conversion timed out (120s limit)")

    if not output_dxf.exists():
        raise ConversionError(
            f"LibreDWG conversion failed. "
            f"stdout: {result.stdout} stderr: {result.stderr}"
        )

    return output_dxf


# ---------------------------------------------------------------------------
# ODA File Converter detection (fallback)
# ---------------------------------------------------------------------------

def _find_oda_converter() -> str | None:
    if settings.oda_converter_path:
        path = Path(settings.oda_converter_path)
        if path.exists():
            return str(path)
    candidates = [
        r"C:\Program Files\ODA\ODAFileConverter\ODAFileConverter.exe",
        r"C:\Program Files (x86)\ODA\ODAFileConverter\ODAFileConverter.exe",
        "/usr/bin/ODAFileConverter",
        "/usr/local/bin/ODAFileConverter",
    ]
    for c in candidates:
        if Path(c).exists():
            return c
    found = shutil.which("ODAFileConverter")
    return found


def is_oda_available() -> bool:
    return _find_oda_converter() is not None


def convert_dwg_to_dxf_oda(dwg_path: Path, output_dir: Path) -> Path:
    """Convert DWG → DXF using ODA File Converter."""
    converter = _find_oda_converter()
    if not converter:
        raise ConversionError("ODA File Converter not found")

    output_dir.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(
            [
                converter,
                str(dwg_path.parent),
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

    output_dxf = output_dir / f"{dwg_path.stem}.dxf"
    if not output_dxf.exists():
        raise ConversionError(
            f"ODA conversion failed. Output: {result.stdout} {result.stderr}"
        )
    return output_dxf


# ---------------------------------------------------------------------------
# Public API – tries converters in priority order
# ---------------------------------------------------------------------------

def get_available_converter() -> str:
    """Return the name of the best available DWG converter."""
    if is_libredwg_available():
        return "libredwg"
    if is_oda_available():
        return "oda"
    return "none"


def convert_dwg_to_dxf(dwg_path: Path, output_dir: Path) -> Path:
    """Convert DWG → DXF. Tries LibreDWG first, then ODA as fallback."""
    errors: list[str] = []

    # 1. Try LibreDWG (free, open-source)
    if is_libredwg_available():
        try:
            return convert_dwg_to_dxf_libredwg(dwg_path, output_dir)
        except ConversionError as e:
            errors.append(f"LibreDWG: {e}")

    # 2. Try ODA File Converter (fallback)
    if is_oda_available():
        try:
            return convert_dwg_to_dxf_oda(dwg_path, output_dir)
        except ConversionError as e:
            errors.append(f"ODA: {e}")

    # 3. No converter available
    if errors:
        raise ConversionError(
            "All DWG converters failed:\n" + "\n".join(errors)
        )

    raise ConversionError(
        "No DWG converter found. Install one of the following:\n"
        "  1. LibreDWG (recommended, free): https://github.com/LibreDWG/libredwg/releases\n"
        "     Windows: download dwg2dxf.exe and set LIBREDWG_PATH in .env\n"
        "     Linux:   sudo apt install libredwg-tools\n"
        "     macOS:   brew install libredwg\n"
        "  2. ODA File Converter: https://www.opendesign.com/guestfiles/oda_file_converter\n"
        "     Set ODA_CONVERTER_PATH in .env"
    )


def convert_pdf_to_dxf(pdf_path: Path, output_dir: Path) -> Path:
    """Convert a CAD-exported PDF to DXF using ODA File Converter.

    Note: LibreDWG does not support PDF→DXF, so ODA is required for this.
    """
    converter = _find_oda_converter()
    if not converter:
        raise ConversionError(
            "ODA File Converter not found. Required for PDF-to-DXF conversion. "
            "For PDF floor plans without ODA, the scanned PDF parser will be used as fallback."
        )

    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        result = subprocess.run(
            [
                converter,
                str(pdf_path.parent),
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

    output_dxf = output_dir / f"{pdf_path.stem}.dxf"
    if not output_dxf.exists():
        raise ConversionError(
            f"PDF conversion failed (may not be a CAD-exported PDF). "
            f"ODA output: {result.stdout} {result.stderr}"
        )

    return output_dxf
