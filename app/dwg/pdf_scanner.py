"""
PDF floor plan parser for professional architectural drawings.

Supports two modes:
1. Vector PDFs (CAD-exported): extracts vector paths directly via PyMuPDF
2. Raster/scanned PDFs: uses OpenCV for line/shape detection

Handles multi-layer architectural plans with walls, doors, windows,
furniture, dimensions, and annotations.
"""
from __future__ import annotations
import logging
import math
from dataclasses import dataclass, field
from pathlib import Path

from app.config import settings
from app.dwg.elements import FloorPlan, FurnitureItem, Opening, Wall

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False
    np = None  # type: ignore[assignment]

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

log = logging.getLogger(__name__)


class ScannerNotAvailable(Exception):
    pass


def is_scanner_available() -> bool:
    return HAS_NUMPY and HAS_PYMUPDF and HAS_OPENCV


# ---------------------------------------------------------------------------
# Color classification for architectural drawings
# ---------------------------------------------------------------------------

@dataclass
class ColorRange:
    """HSV color range for classifying drawing elements."""
    name: str
    h_min: int
    h_max: int
    s_min: int
    s_max: int
    v_min: int
    v_max: int


# Common color conventions in architectural PDFs
WALL_COLORS = [
    ColorRange("black", 0, 180, 0, 50, 0, 80),       # Black/dark gray walls
    ColorRange("dark_gray", 0, 180, 0, 30, 80, 130),  # Dark gray walls
]
DOOR_COLORS = [
    ColorRange("blue", 100, 130, 50, 255, 50, 255),
    ColorRange("red", 0, 10, 50, 255, 50, 255),
    ColorRange("red2", 170, 180, 50, 255, 50, 255),
]
WINDOW_COLORS = [
    ColorRange("cyan", 80, 100, 50, 255, 50, 255),
    ColorRange("light_blue", 95, 115, 30, 255, 100, 255),
]
FURNITURE_COLORS = [
    ColorRange("green", 35, 80, 50, 255, 50, 255),
    ColorRange("brown", 10, 25, 50, 200, 50, 200),
    ColorRange("orange", 10, 30, 100, 255, 100, 255),
]


def _color_in_ranges(hsv_pixel: tuple, ranges: list[ColorRange]) -> bool:
    h, s, v = hsv_pixel
    for cr in ranges:
        if cr.h_min <= h <= cr.h_max and cr.s_min <= s <= cr.s_max and cr.v_min <= v <= cr.v_max:
            return True
    return False


# ---------------------------------------------------------------------------
# Vector PDF extraction (for CAD-exported PDFs)
# ---------------------------------------------------------------------------

@dataclass
class VectorLine:
    x1: float
    y1: float
    x2: float
    y2: float
    width: float = 1.0
    color: tuple = (0, 0, 0)
    layer_hint: str = ""


@dataclass
class VectorRect:
    x: float
    y: float
    w: float
    h: float
    color: tuple = (0, 0, 0)
    filled: bool = False


def _extract_vector_paths(pdf_path: Path, page_num: int = 0) -> tuple[list[VectorLine], list[VectorRect]]:
    """Extract vector line segments and rectangles from a PDF page."""
    doc = fitz.open(str(pdf_path))
    page = doc[page_num]

    lines: list[VectorLine] = []
    rects: list[VectorRect] = []

    # Get the page's drawing commands
    paths = page.get_drawings()

    for path in paths:
        color = path.get("color", (0, 0, 0))
        fill = path.get("fill")
        stroke_width = path.get("width", 1.0)

        if color is None:
            color = (0, 0, 0)

        for item in path.get("items", []):
            cmd = item[0]

            if cmd == "l":  # Line
                p1, p2 = item[1], item[2]
                lines.append(VectorLine(
                    x1=p1.x, y1=p1.y, x2=p2.x, y2=p2.y,
                    width=stroke_width or 1.0,
                    color=color,
                ))
            elif cmd == "re":  # Rectangle
                rect = item[1]
                rects.append(VectorRect(
                    x=rect.x0, y=rect.y0,
                    w=rect.width, h=rect.height,
                    color=color,
                    filled=fill is not None,
                ))
            elif cmd == "c":  # Cubic bezier curve - approximate as line
                p1, p4 = item[1], item[4]
                lines.append(VectorLine(
                    x1=p1.x, y1=p1.y, x2=p4.x, y2=p4.y,
                    width=stroke_width or 1.0,
                    color=color,
                ))
            elif cmd == "qu":  # Quad bezier - approximate as line
                p1, p3 = item[1], item[3]
                lines.append(VectorLine(
                    x1=p1.x, y1=p1.y, x2=p3.x, y2=p3.y,
                    width=stroke_width or 1.0,
                    color=color,
                ))

    doc.close()
    return lines, rects


def _classify_line_as_element(line: VectorLine, page_height: float) -> str:
    """Classify a vector line based on stroke width and color."""
    r, g, b = (line.color[0], line.color[1], line.color[2]) if len(line.color) >= 3 else (0, 0, 0)

    # Thick black/dark lines are walls
    if line.width >= 2.0 and (r + g + b) < 0.5:
        return "wall"
    # Medium black lines could also be walls
    if line.width >= 1.0 and (r + g + b) < 0.3:
        return "wall"
    # Blue lines = doors or windows
    if b > 0.5 and r < 0.3 and g < 0.3:
        return "door"
    # Cyan = windows
    if g > 0.5 and b > 0.5 and r < 0.3:
        return "window"
    # Thin dark lines = wall detail
    if line.width >= 0.5 and (r + g + b) < 0.5:
        return "wall"
    return "ignore"


def _parse_vector_pdf(pdf_path: Path, page_num: int = 0) -> FloorPlan:
    """Parse a CAD-exported PDF using vector path extraction."""
    doc = fitz.open(str(pdf_path))
    page = doc[page_num]
    page_height = page.rect.height
    # PDF points to mm conversion (1 point = 0.3528 mm)
    pt_to_mm = 25.4 / 72.0
    doc.close()

    lines, rects = _extract_vector_paths(pdf_path, page_num)
    plan = FloorPlan(source_filename=pdf_path.name, units="mm")

    if not lines and not rects:
        return plan

    log.info(f"Vector PDF: found {len(lines)} lines, {len(rects)} rectangles")

    # Classify and add lines
    for vl in lines:
        length_pt = math.hypot(vl.x2 - vl.x1, vl.y2 - vl.y1)
        length_mm = length_pt * pt_to_mm
        if length_mm < 10:
            continue

        element_type = _classify_line_as_element(vl, page_height)

        start = (vl.x1 * pt_to_mm, (page_height - vl.y1) * pt_to_mm)
        end = (vl.x2 * pt_to_mm, (page_height - vl.y2) * pt_to_mm)

        if element_type == "wall":
            thickness = max(settings.default_wall_thickness, vl.width * pt_to_mm * 10)
            plan.walls.append(Wall(
                start=start, end=end,
                thickness=min(thickness, 400),
                height=settings.default_wall_height,
                layer="pdf_walls",
            ))
        elif element_type == "door":
            mid = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2)
            plan.openings.append(Opening(
                type="door",
                position=mid,
                width=length_mm,
                height=2100.0,
                rotation=math.degrees(math.atan2(end[1] - start[1], end[0] - start[0])),
                layer="pdf_doors",
            ))
        elif element_type == "window":
            mid = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2)
            plan.openings.append(Opening(
                type="window",
                position=mid,
                width=length_mm,
                height=1200.0,
                sill_height=900.0,
                rotation=math.degrees(math.atan2(end[1] - start[1], end[0] - start[0])),
                layer="pdf_windows",
            ))

    # Add rectangles as furniture
    for vr in rects:
        w_mm = vr.w * pt_to_mm
        h_mm = vr.h * pt_to_mm
        if w_mm < 50 or h_mm < 50:
            continue
        # Skip very large rects (likely borders or title blocks)
        if w_mm > 10000 or h_mm > 10000:
            continue

        cx = (vr.x + vr.w / 2) * pt_to_mm
        cy = (page_height - vr.y - vr.h / 2) * pt_to_mm

        # Filled rects in medium size range = furniture
        if vr.filled and 100 < w_mm < 3000 and 100 < h_mm < 3000:
            plan.furniture.append(FurnitureItem(
                block_name="detected_rect",
                position=(cx, cy),
                scale=(w_mm / 600, h_mm / 600, 1.0),
                layer="pdf_furniture",
            ))

    plan.compute_bounds()
    return plan


# ---------------------------------------------------------------------------
# Raster/scanned PDF extraction (OpenCV-based)
# ---------------------------------------------------------------------------

def _pdf_page_to_image(pdf_path: Path, page_num: int = 0, dpi: int = 300) -> np.ndarray:
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
    elif pix.n == 3:
        img = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
    elif pix.n == 1:
        img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    doc.close()
    return img


def _preprocess_image(img: np.ndarray) -> dict[str, np.ndarray]:
    """Preprocess image and create multiple filtered versions for better detection."""
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)

    # Adaptive threshold for varying lighting in scanned docs
    adaptive = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV, 21, 10
    )

    # Standard binary threshold
    _, binary = cv2.threshold(gray, 127, 255, cv2.THRESH_BINARY_INV)

    # Morphological operations to separate thick (wall) vs thin lines
    # Thick lines (walls): erode to keep only thick features
    kernel_thick = np.ones((5, 5), np.uint8)
    thick_mask = cv2.erode(adaptive, kernel_thick, iterations=2)
    thick_mask = cv2.dilate(thick_mask, kernel_thick, iterations=2)

    # Thin lines (details): subtract thick from all
    thin_mask = cv2.subtract(adaptive, thick_mask)

    # Edge detection
    edges = cv2.Canny(gray, 30, 100, apertureSize=3)
    edges_dilated = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=1)

    return {
        "gray": gray,
        "hsv": hsv,
        "adaptive": adaptive,
        "binary": binary,
        "thick_mask": thick_mask,
        "thin_mask": thin_mask,
        "edges": edges_dilated,
    }


def _detect_walls_advanced(preprocessed: dict, dpi: int, scale: float) -> list[Wall]:
    """Detect walls using multiple strategies for professional drawings."""
    walls: list[Wall] = []

    # Strategy 1: Hough lines on thick mask (structural walls)
    thick = preprocessed["thick_mask"]
    lines = cv2.HoughLinesP(
        thick, rho=1, theta=np.pi / 180,
        threshold=50, minLineLength=int(dpi * 0.3), maxLineGap=int(dpi * 0.1)
    )
    if lines is not None:
        for l in lines:
            x1, y1, x2, y2 = l[0]
            start = (_px_to_mm(x1, dpi, scale), _px_to_mm(y1, dpi, scale))
            end = (_px_to_mm(x2, dpi, scale), _px_to_mm(y2, dpi, scale))
            length = math.hypot(end[0] - start[0], end[1] - start[1])
            if length > 200:
                walls.append(Wall(
                    start=start, end=end,
                    thickness=settings.default_wall_thickness,
                    height=settings.default_wall_height,
                    layer="scanned_walls_thick",
                ))

    # Strategy 2: Hough lines on edges (all lines, including thinner walls)
    edges = preprocessed["edges"]
    lines2 = cv2.HoughLinesP(
        edges, rho=1, theta=np.pi / 180,
        threshold=80, minLineLength=int(dpi * 0.5), maxLineGap=int(dpi * 0.05)
    )
    if lines2 is not None:
        for l in lines2:
            x1, y1, x2, y2 = l[0]
            start = (_px_to_mm(x1, dpi, scale), _px_to_mm(y1, dpi, scale))
            end = (_px_to_mm(x2, dpi, scale), _px_to_mm(y2, dpi, scale))
            length = math.hypot(end[0] - start[0], end[1] - start[1])
            # Only add if not too close to an existing wall
            if length > 300 and not _near_existing_wall(start, end, walls, 50):
                walls.append(Wall(
                    start=start, end=end,
                    thickness=settings.default_wall_thickness * 0.6,
                    height=settings.default_wall_height,
                    layer="scanned_walls_thin",
                ))

    # Strategy 3: Contour-based wall detection (closed rooms)
    adaptive = preprocessed["adaptive"]
    contours, hierarchy = cv2.findContours(
        adaptive, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE
    )
    if contours and hierarchy is not None:
        for i, cnt in enumerate(contours):
            area = cv2.contourArea(cnt)
            area_mm2 = (_px_to_mm(math.sqrt(area), dpi, scale)) ** 2
            # Room-sized contours (1m² to 100m²)
            if 1_000_000 < area_mm2 < 100_000_000:
                approx = cv2.approxPolyDP(cnt, 0.01 * cv2.arcLength(cnt, True), True)
                points = [(p[0][0], p[0][1]) for p in approx]
                for j in range(len(points)):
                    p1 = points[j]
                    p2 = points[(j + 1) % len(points)]
                    start = (_px_to_mm(p1[0], dpi, scale), _px_to_mm(p1[1], dpi, scale))
                    end = (_px_to_mm(p2[0], dpi, scale), _px_to_mm(p2[1], dpi, scale))
                    seg_len = math.hypot(end[0] - start[0], end[1] - start[1])
                    if seg_len > 500 and not _near_existing_wall(start, end, walls, 100):
                        walls.append(Wall(
                            start=start, end=end,
                            thickness=settings.default_wall_thickness,
                            height=settings.default_wall_height,
                            layer="scanned_walls_contour",
                        ))

    return walls


def _detect_openings_advanced(
    preprocessed: dict, img: np.ndarray, walls: list[Wall],
    dpi: int, scale: float,
) -> list[Opening]:
    """Detect doors and windows from scanned architectural drawings."""
    openings: list[Opening] = []
    gray = preprocessed["gray"]
    hsv = preprocessed["hsv"]

    # Door detection: look for arcs (door swings)
    gray_blur = cv2.medianBlur(gray, 5)
    circles = cv2.HoughCircles(
        gray_blur, cv2.HOUGH_GRADIENT, dp=1.2, minDist=int(dpi * 0.3),
        param1=50, param2=25, minRadius=int(dpi * 0.15), maxRadius=int(dpi * 0.8)
    )
    if circles is not None:
        for c in circles[0]:
            cx, cy, radius = int(c[0]), int(c[1]), int(c[2])
            pos = (_px_to_mm(cx, dpi, scale), _px_to_mm(cy, dpi, scale))
            width = _px_to_mm(radius * 2, dpi, scale)
            if 500 < width < 2500:
                openings.append(Opening(
                    type="door",
                    position=pos,
                    width=width,
                    height=2100.0,
                    layer="scanned_doors",
                ))

    # Window detection: look for parallel thin lines along walls
    # (windows typically appear as thin double lines on walls)
    thin = preprocessed["thin_mask"]
    thin_lines = cv2.HoughLinesP(
        thin, rho=1, theta=np.pi / 180,
        threshold=30, minLineLength=int(dpi * 0.2), maxLineGap=5
    )
    if thin_lines is not None:
        window_candidates: list[tuple] = []
        for l in thin_lines:
            x1, y1, x2, y2 = l[0]
            mid = (_px_to_mm((x1 + x2) / 2, dpi, scale), _px_to_mm((y1 + y2) / 2, dpi, scale))
            length = _px_to_mm(math.hypot(x2 - x1, y2 - y1), dpi, scale)
            angle = math.degrees(math.atan2(y2 - y1, x2 - x1))
            if 400 < length < 2500:
                window_candidates.append((mid, length, angle))

        # Find pairs of parallel lines close together (window pattern)
        used = set()
        for i in range(len(window_candidates)):
            if i in used:
                continue
            for j in range(i + 1, len(window_candidates)):
                if j in used:
                    continue
                mid_i, len_i, ang_i = window_candidates[i]
                mid_j, len_j, ang_j = window_candidates[j]
                # Similar angle and length, close together
                angle_diff = abs(ang_i - ang_j) % 180
                dist = math.hypot(mid_i[0] - mid_j[0], mid_i[1] - mid_j[1])
                if angle_diff < 10 and abs(len_i - len_j) < 200 and 30 < dist < 300:
                    center = ((mid_i[0] + mid_j[0]) / 2, (mid_i[1] + mid_j[1]) / 2)
                    openings.append(Opening(
                        type="window",
                        position=center,
                        width=(len_i + len_j) / 2,
                        height=1200.0,
                        sill_height=900.0,
                        rotation=ang_i,
                        layer="scanned_windows",
                    ))
                    used.add(i)
                    used.add(j)
                    break

    # Color-based detection: look for colored elements
    h, w_img = hsv.shape[:2]
    for y_px in range(0, h, int(dpi * 0.1)):
        for x_px in range(0, w_img, int(dpi * 0.1)):
            pixel_hsv = tuple(hsv[y_px, x_px])
            pos = (_px_to_mm(x_px, dpi, scale), _px_to_mm(y_px, dpi, scale))
            if _color_in_ranges(pixel_hsv, DOOR_COLORS):
                # Check if there's a cluster of door-colored pixels
                region = hsv[
                    max(0, y_px - 5):min(h, y_px + 5),
                    max(0, x_px - 5):min(w_img, x_px + 5)
                ]
                if region.size > 0:
                    door_pixels = sum(
                        1 for ry in range(region.shape[0])
                        for rx in range(region.shape[1])
                        if _color_in_ranges(tuple(region[ry, rx]), DOOR_COLORS)
                    )
                    if door_pixels > region.shape[0] * region.shape[1] * 0.3:
                        if not _near_existing_opening(pos, openings, 500):
                            openings.append(Opening(
                                type="door", position=pos,
                                width=900.0, height=2100.0,
                                layer="scanned_doors_color",
                            ))

    return openings


def _detect_furniture_advanced(
    preprocessed: dict, img: np.ndarray, walls: list[Wall],
    dpi: int, scale: float,
) -> list[FurnitureItem]:
    """Detect furniture from scanned architectural drawings."""
    furniture: list[FurnitureItem] = []
    adaptive = preprocessed["adaptive"]

    # Find rectangular contours that aren't walls
    contours, _ = cv2.findContours(adaptive, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)

    for cnt in contours:
        area = cv2.contourArea(cnt)
        area_mm2 = (_px_to_mm(math.sqrt(area), dpi, scale)) ** 2

        # Furniture-sized objects (0.01m² to 6m²)
        if 10_000 < area_mm2 < 6_000_000:
            approx = cv2.approxPolyDP(cnt, 0.02 * cv2.arcLength(cnt, True), True)
            if 4 <= len(approx) <= 8:
                x, y, w, h = cv2.boundingRect(cnt)
                cx = _px_to_mm(x + w / 2, dpi, scale)
                cy = _px_to_mm(y + h / 2, dpi, scale)
                w_mm = _px_to_mm(w, dpi, scale)
                h_mm = _px_to_mm(h, dpi, scale)

                # Skip if it overlaps with a wall
                if _point_on_wall((cx, cy), walls, 200):
                    continue

                # Guess furniture type from aspect ratio and size
                block_name = _guess_furniture_type(w_mm, h_mm)

                furniture.append(FurnitureItem(
                    block_name=block_name,
                    position=(cx, cy),
                    scale=(w_mm / 600, h_mm / 600, 1.0),
                    layer="scanned_furniture",
                ))

    return furniture


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _px_to_mm(value: float, dpi: int, scale: float = 1.0) -> float:
    return value / dpi * 25.4 * scale


def _near_existing_wall(
    start: tuple, end: tuple, walls: list[Wall], threshold: float,
) -> bool:
    mid = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2)
    for w in walls:
        w_mid = w.midpoint
        if math.hypot(mid[0] - w_mid[0], mid[1] - w_mid[1]) < threshold:
            return True
    return False


def _near_existing_opening(pos: tuple, openings: list[Opening], threshold: float) -> bool:
    for o in openings:
        if math.hypot(pos[0] - o.position[0], pos[1] - o.position[1]) < threshold:
            return True
    return False


def _point_on_wall(point: tuple, walls: list[Wall], threshold: float) -> bool:
    from app.geometry.utils import point_to_line_distance
    for w in walls:
        if point_to_line_distance(point, w.start, w.end) < threshold:
            return True
    return False


def _guess_furniture_type(w_mm: float, h_mm: float) -> str:
    area = w_mm * h_mm
    ratio = max(w_mm, h_mm) / max(min(w_mm, h_mm), 1)

    if 1_500_000 < area < 4_000_000 and ratio < 1.5:
        return "bed"
    if 800_000 < area < 2_000_000 and ratio > 1.5:
        return "sofa"
    if 400_000 < area < 1_200_000:
        return "table"
    if 100_000 < area < 400_000:
        return "desk" if ratio > 1.5 else "chair"
    if h_mm > 1500 and w_mm < 600:
        return "cabinet"
    return "detected_furniture"


# ---------------------------------------------------------------------------
# Multi-page support
# ---------------------------------------------------------------------------

def _get_best_page(pdf_path: Path) -> int:
    """Find the page most likely to be the floor plan (largest, most content)."""
    doc = fitz.open(str(pdf_path))
    best_page = 0
    best_score = 0

    for i in range(len(doc)):
        page = doc[i]
        # Score based on: number of drawings + page size
        paths = page.get_drawings()
        text_len = len(page.get_text())
        # Floor plans have many paths and relatively little text
        score = len(paths) * 10 - text_len
        if score > best_score:
            best_score = score
            best_page = i

    doc.close()
    return best_page


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def parse_scanned_pdf(
    pdf_path: Path,
    page_num: int | None = None,
    dpi: int = 300,
    drawing_scale: float = 50.0,
) -> FloorPlan:
    """Parse a PDF floor plan using vector extraction + computer vision fallback.

    Handles professional architectural drawings with multiple layers.
    Automatically selects the best page if page_num is not specified.
    """
    if not is_scanner_available():
        raise ScannerNotAvailable(
            "Scanned PDF support requires PyMuPDF, OpenCV, and NumPy. "
            "Install with: pip install pymupdf opencv-python numpy"
        )

    # Auto-select the best page
    if page_num is None:
        page_num = _get_best_page(pdf_path)
        log.info(f"Auto-selected page {page_num} as floor plan")

    # Try vector extraction first (much more accurate for CAD-exported PDFs)
    plan = _parse_vector_pdf(pdf_path, page_num)

    if plan.walls:
        log.info(
            f"Vector extraction: {len(plan.walls)} walls, "
            f"{len(plan.openings)} openings, {len(plan.furniture)} furniture"
        )
        return plan

    # Fall back to raster/scanned analysis
    log.info("No vector paths found, falling back to raster analysis")
    img = _pdf_page_to_image(pdf_path, page_num, dpi)
    preprocessed = _preprocess_image(img)

    plan = FloorPlan(source_filename=pdf_path.name, units="mm")
    plan.walls = _detect_walls_advanced(preprocessed, dpi, drawing_scale)
    plan.openings = _detect_openings_advanced(preprocessed, img, plan.walls, dpi, drawing_scale)
    plan.furniture = _detect_furniture_advanced(preprocessed, img, plan.walls, dpi, drawing_scale)
    plan.compute_bounds()

    log.info(
        f"Raster extraction: {len(plan.walls)} walls, "
        f"{len(plan.openings)} openings, {len(plan.furniture)} furniture"
    )

    return plan
