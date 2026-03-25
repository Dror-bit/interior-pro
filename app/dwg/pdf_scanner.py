"""
Scanned PDF floor plan parser.

Uses PyMuPDF (fitz) to extract images from PDFs,
then OpenCV to detect lines (walls), rectangles (furniture),
and circles/arcs (door swings).
"""
from __future__ import annotations
import math
from pathlib import Path

import numpy as np

from app.config import settings
from app.dwg.elements import FloorPlan, FurnitureItem, Opening, Wall

try:
    import fitz  # PyMuPDF
    HAS_PYMUPDF = True
except ImportError:
    HAS_PYMUPDF = False

try:
    import cv2
    HAS_OPENCV = True
except ImportError:
    HAS_OPENCV = False


class ScannerNotAvailable(Exception):
    pass


def is_scanner_available() -> bool:
    return HAS_PYMUPDF and HAS_OPENCV


def _pdf_page_to_image(pdf_path: Path, page_num: int = 0, dpi: int = 200) -> np.ndarray:
    """Extract a page from PDF as a numpy image array."""
    if not HAS_PYMUPDF:
        raise ScannerNotAvailable("PyMuPDF (fitz) not installed. pip install pymupdf")
    doc = fitz.open(str(pdf_path))
    page = doc[page_num]
    mat = fitz.Matrix(dpi / 72, dpi / 72)
    pix = page.get_pixmap(matrix=mat)
    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.h, pix.w, pix.n)
    if pix.n == 4:
        img = cv2.cvtColor(img, cv2.COLOR_RGBA2BGR)
    elif pix.n == 1:
        img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    doc.close()
    return img


def _detect_lines(img: np.ndarray, min_length: int = 50) -> list[tuple]:
    """Detect straight lines using Hough Line Transform."""
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 50, 150, apertureSize=3)

    # Dilate to connect nearby edges
    kernel = np.ones((3, 3), np.uint8)
    edges = cv2.dilate(edges, kernel, iterations=1)

    lines = cv2.HoughLinesP(
        edges, rho=1, theta=np.pi / 180,
        threshold=80, minLineLength=min_length, maxLineGap=10
    )

    if lines is None:
        return []
    return [(l[0][0], l[0][1], l[0][2], l[0][3]) for l in lines]


def _detect_rectangles(img: np.ndarray, min_area: int = 500) -> list[tuple]:
    """Detect rectangular shapes (potential furniture)."""
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    _, thresh = cv2.threshold(gray, 200, 255, cv2.THRESH_BINARY_INV)

    contours, _ = cv2.findContours(thresh, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)

    rects = []
    for cnt in contours:
        area = cv2.contourArea(cnt)
        if area < min_area:
            continue
        approx = cv2.approxPolyDP(cnt, 0.02 * cv2.arcLength(cnt, True), True)
        if len(approx) == 4:
            x, y, w, h = cv2.boundingRect(approx)
            rects.append((x, y, w, h))
    return rects


def _detect_arcs(img: np.ndarray) -> list[tuple]:
    """Detect circles/arcs (potential door swings)."""
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    gray = cv2.medianBlur(gray, 5)

    circles = cv2.HoughCircles(
        gray, cv2.HOUGH_GRADIENT, dp=1, minDist=30,
        param1=50, param2=30, minRadius=10, maxRadius=100
    )

    if circles is None:
        return []
    return [(int(c[0]), int(c[1]), int(c[2])) for c in circles[0]]


def _pixel_to_mm(value: float, dpi: int, scale: float = 1.0) -> float:
    """Convert pixel coordinates to mm using DPI and drawing scale."""
    inches = value / dpi
    mm = inches * 25.4
    return mm * scale


def parse_scanned_pdf(
    pdf_path: Path,
    page_num: int = 0,
    dpi: int = 200,
    drawing_scale: float = 50.0,  # e.g., 1:50
) -> FloorPlan:
    """Parse a scanned PDF floor plan using computer vision."""
    if not is_scanner_available():
        raise ScannerNotAvailable(
            "Scanned PDF support requires PyMuPDF and OpenCV. "
            "Install with: pip install pymupdf opencv-python"
        )

    img = _pdf_page_to_image(pdf_path, page_num, dpi)
    plan = FloorPlan(source_filename=pdf_path.name, units="mm")

    # Detect walls from lines
    lines = _detect_lines(img, min_length=50)
    for x1, y1, x2, y2 in lines:
        start = (
            _pixel_to_mm(x1, dpi, drawing_scale),
            _pixel_to_mm(y1, dpi, drawing_scale),
        )
        end = (
            _pixel_to_mm(x2, dpi, drawing_scale),
            _pixel_to_mm(y2, dpi, drawing_scale),
        )
        # Filter out very short lines
        length = math.hypot(end[0] - start[0], end[1] - start[1])
        if length > 100:  # Skip lines shorter than 100mm
            plan.walls.append(Wall(
                start=start, end=end,
                thickness=settings.default_wall_thickness,
                height=settings.default_wall_height,
                layer="scanned_walls",
            ))

    # Detect furniture from rectangles
    rects = _detect_rectangles(img, min_area=1000)
    for x, y, w, h in rects:
        cx = _pixel_to_mm(x + w / 2, dpi, drawing_scale)
        cy = _pixel_to_mm(y + h / 2, dpi, drawing_scale)
        plan.furniture.append(FurnitureItem(
            block_name="detected_rect",
            position=(cx, cy),
            scale=(
                _pixel_to_mm(w, dpi, drawing_scale) / 600,
                _pixel_to_mm(h, dpi, drawing_scale) / 600,
                1.0,
            ),
            layer="scanned_furniture",
        ))

    # Detect doors from arcs
    arcs = _detect_arcs(img)
    for cx, cy, radius in arcs:
        pos = (
            _pixel_to_mm(cx, dpi, drawing_scale),
            _pixel_to_mm(cy, dpi, drawing_scale),
        )
        width = _pixel_to_mm(radius * 2, dpi, drawing_scale)
        if 400 < width < 2000:  # Reasonable door width range
            plan.openings.append(Opening(
                type="door",
                position=pos,
                width=width,
                height=2100.0,
                layer="scanned_doors",
            ))

    plan.compute_bounds()
    return plan
