from __future__ import annotations
import math
from xml.etree.ElementTree import Element, SubElement, tostring

from app.dwg.elements import FloorPlan

COLORS = {
    "wall": "#2C3E50",
    "door": "#3498DB",
    "window": "#1ABC9C",
    "furniture": "#E67E22",
    "background": "#FAFAFA",
}

SVG_PADDING = 40
SVG_DEFAULT_SIZE = 800


def render_svg(plan: FloorPlan, width: int = SVG_DEFAULT_SIZE) -> str:
    if not plan.walls and not plan.openings and not plan.furniture:
        return _empty_svg(width)

    plan.compute_bounds()
    min_x, min_y, max_x, max_y = plan.bounds

    data_w = max_x - min_x or 1
    data_h = max_y - min_y or 1
    aspect = data_h / data_w
    height = int(width * aspect)

    scale = (width - 2 * SVG_PADDING) / data_w

    def tx(x: float) -> float:
        return SVG_PADDING + (x - min_x) * scale

    def ty(y: float) -> float:
        # Flip Y axis (SVG Y goes down, CAD Y goes up)
        return height - SVG_PADDING - (y - min_y) * scale

    svg = Element("svg", {
        "xmlns": "http://www.w3.org/2000/svg",
        "width": str(width),
        "height": str(height),
        "viewBox": f"0 0 {width} {height}",
    })

    # Background
    SubElement(svg, "rect", {
        "width": str(width), "height": str(height),
        "fill": COLORS["background"],
    })

    # Walls
    walls_g = SubElement(svg, "g", {"id": "walls"})
    for wall in plan.walls:
        thickness_px = max(2, wall.thickness * scale)
        SubElement(walls_g, "line", {
            "x1": f"{tx(wall.start[0]):.1f}",
            "y1": f"{ty(wall.start[1]):.1f}",
            "x2": f"{tx(wall.end[0]):.1f}",
            "y2": f"{ty(wall.end[1]):.1f}",
            "stroke": wall.color or COLORS["wall"],
            "stroke-width": f"{thickness_px:.1f}",
            "stroke-linecap": "round",
        })

    # Openings
    openings_g = SubElement(svg, "g", {"id": "openings"})
    for opening in plan.openings:
        ox = tx(opening.position[0])
        oy = ty(opening.position[1])
        r = opening.width * scale / 2

        color = COLORS["door"] if opening.type == "door" else COLORS["window"]

        if opening.type == "door":
            # Door: arc + line
            SubElement(openings_g, "circle", {
                "cx": f"{ox:.1f}", "cy": f"{oy:.1f}",
                "r": f"{r:.1f}",
                "fill": "none", "stroke": color,
                "stroke-width": "2",
                "stroke-dasharray": "4,2",
            })
            SubElement(openings_g, "line", {
                "x1": f"{ox - r:.1f}", "y1": f"{oy:.1f}",
                "x2": f"{ox + r:.1f}", "y2": f"{oy:.1f}",
                "stroke": color, "stroke-width": "2",
            })
        else:
            # Window: double line
            angle = opening.rotation * math.pi / 180
            dx = r * math.cos(angle)
            dy = r * math.sin(angle)
            SubElement(openings_g, "line", {
                "x1": f"{ox - dx:.1f}", "y1": f"{oy + dy:.1f}",
                "x2": f"{ox + dx:.1f}", "y2": f"{oy - dy:.1f}",
                "stroke": color, "stroke-width": "3",
            })
            offset = 3
            SubElement(openings_g, "line", {
                "x1": f"{ox - dx:.1f}", "y1": f"{oy + dy + offset:.1f}",
                "x2": f"{ox + dx:.1f}", "y2": f"{oy - dy + offset:.1f}",
                "stroke": color, "stroke-width": "3",
            })

    # Furniture
    furn_g = SubElement(svg, "g", {"id": "furniture"})
    for item in plan.furniture:
        fx = tx(item.position[0])
        fy = ty(item.position[1])
        size = 20 * item.scale[0]

        rect = SubElement(furn_g, "rect", {
            "x": f"{fx - size / 2:.1f}",
            "y": f"{fy - size / 2:.1f}",
            "width": f"{size:.1f}",
            "height": f"{size:.1f}",
            "fill": item.color or COLORS["furniture"],
            "fill-opacity": "0.5",
            "stroke": COLORS["furniture"],
            "stroke-width": "1.5",
            "rx": "2",
        })
        if item.rotation:
            rect.set("transform", f"rotate({-item.rotation} {fx:.1f} {fy:.1f})")

        # Label
        SubElement(furn_g, "text", {
            "x": f"{fx:.1f}", "y": f"{fy + 3:.1f}",
            "text-anchor": "middle",
            "font-size": "8", "font-family": "Arial",
            "fill": "#333",
        }).text = item.block_name[:6]

    # Legend
    _add_legend(svg, width, height)

    return '<?xml version="1.0" encoding="UTF-8"?>\n' + tostring(svg, encoding="unicode")


def _add_legend(svg: Element, width: int, height: int) -> None:
    legend = SubElement(svg, "g", {"id": "legend", "transform": f"translate({width - 130}, 10)"})
    SubElement(legend, "rect", {
        "width": "120", "height": "90",
        "fill": "white", "fill-opacity": "0.9",
        "stroke": "#ccc", "rx": "4",
    })
    items = [
        ("Walls", COLORS["wall"]),
        ("Doors", COLORS["door"]),
        ("Windows", COLORS["window"]),
        ("Furniture", COLORS["furniture"]),
    ]
    for i, (label, color) in enumerate(items):
        y = 20 + i * 20
        SubElement(legend, "rect", {
            "x": "8", "y": str(y - 6), "width": "14", "height": "10",
            "fill": color, "rx": "2",
        })
        SubElement(legend, "text", {
            "x": "28", "y": str(y + 3),
            "font-size": "11", "font-family": "Arial", "fill": "#333",
        }).text = label


def _empty_svg(width: int) -> str:
    svg = Element("svg", {
        "xmlns": "http://www.w3.org/2000/svg",
        "width": str(width), "height": str(width // 2),
        "viewBox": f"0 0 {width} {width // 2}",
    })
    SubElement(svg, "rect", {
        "width": str(width), "height": str(width // 2),
        "fill": COLORS["background"],
    })
    SubElement(svg, "text", {
        "x": str(width // 2), "y": str(width // 4),
        "text-anchor": "middle", "font-size": "16",
        "font-family": "Arial", "fill": "#999",
    }).text = "No elements found in file"
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + tostring(svg, encoding="unicode")
