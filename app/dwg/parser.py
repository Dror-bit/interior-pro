from __future__ import annotations
import ezdxf
from ezdxf.document import Drawing
from ezdxf.entities import DXFEntity, Insert, Line, LWPolyline
from pathlib import Path

from app.config import settings
from app.dwg.elements import FloorPlan, FurnitureItem, Opening, Wall
from app.dwg.layer_mapping import LayerMapper

# AutoCAD Color Index to hex RGB (first 10 standard colors)
ACI_COLORS = {
    1: "#FF0000",  # Red
    2: "#FFFF00",  # Yellow
    3: "#00FF00",  # Green
    4: "#00FFFF",  # Cyan
    5: "#0000FF",  # Blue
    6: "#FF00FF",  # Magenta
    7: "#FFFFFF",  # White/Black
    8: "#808080",  # Dark grey
    9: "#C0C0C0",  # Light grey
}


def _get_entity_color(entity: DXFEntity) -> str | None:
    try:
        color_index = entity.dxf.color
        if color_index and color_index in ACI_COLORS:
            return ACI_COLORS[color_index]
    except AttributeError:
        pass
    return None


def _extract_walls_from_line(entity: Line, layer: str) -> Wall:
    return Wall(
        start=(entity.dxf.start.x, entity.dxf.start.y),
        end=(entity.dxf.end.x, entity.dxf.end.y),
        thickness=settings.default_wall_thickness,
        height=settings.default_wall_height,
        color=_get_entity_color(entity),
        layer=layer,
    )


def _extract_walls_from_polyline(entity: LWPolyline, layer: str) -> list[Wall]:
    walls = []
    points = list(entity.get_points(format="xy"))
    if not points:
        return walls
    for i in range(len(points) - 1):
        walls.append(
            Wall(
                start=points[i],
                end=points[i + 1],
                thickness=settings.default_wall_thickness,
                height=settings.default_wall_height,
                color=_get_entity_color(entity),
                layer=layer,
            )
        )
    if entity.closed and len(points) > 2:
        walls.append(
            Wall(
                start=points[-1],
                end=points[0],
                thickness=settings.default_wall_thickness,
                height=settings.default_wall_height,
                color=_get_entity_color(entity),
                layer=layer,
            )
        )
    return walls


def _extract_opening(entity: Insert, layer: str, opening_type: str) -> Opening:
    sill = 0.0 if opening_type == "door" else 900.0
    height = 2100.0 if opening_type == "door" else 1200.0

    # Try to get dimensions from block attributes
    width = 900.0
    for attrib in entity.attribs:
        tag = attrib.dxf.tag.upper()
        if tag in ("WIDTH", "W"):
            try:
                width = float(attrib.dxf.text)
            except ValueError:
                pass
        elif tag in ("HEIGHT", "H"):
            try:
                height = float(attrib.dxf.text)
            except ValueError:
                pass

    return Opening(
        type=opening_type,
        position=(entity.dxf.insert.x, entity.dxf.insert.y),
        width=width,
        height=height,
        sill_height=sill,
        rotation=entity.dxf.rotation if hasattr(entity.dxf, "rotation") else 0.0,
        layer=layer,
    )


def _extract_furniture(entity: Insert, layer: str) -> FurnitureItem:
    scale = (
        entity.dxf.xscale if hasattr(entity.dxf, "xscale") else 1.0,
        entity.dxf.yscale if hasattr(entity.dxf, "yscale") else 1.0,
        entity.dxf.zscale if hasattr(entity.dxf, "zscale") else 1.0,
    )
    return FurnitureItem(
        block_name=entity.dxf.name,
        position=(entity.dxf.insert.x, entity.dxf.insert.y),
        rotation=entity.dxf.rotation if hasattr(entity.dxf, "rotation") else 0.0,
        scale=scale,
        color=_get_entity_color(entity),
        layer=layer,
    )


def parse_dxf(
    file_path: Path,
    custom_layer_mapping: dict[str, str] | None = None,
) -> FloorPlan:
    doc: Drawing = ezdxf.readfile(str(file_path))
    msp = doc.modelspace()

    mapper = LayerMapper(custom_layer_mapping)

    # Detect all layers
    all_layers = [layer.dxf.name for layer in doc.layers]
    layer_types = mapper.classify_layers(all_layers)

    plan = FloorPlan(source_filename=file_path.name)

    # Detect units from header
    try:
        insunits = doc.header.get("$INSUNITS", 0)
        unit_map = {1: "inches", 2: "feet", 4: "mm", 5: "cm", 6: "m"}
        plan.units = unit_map.get(insunits, "mm")
    except Exception:
        plan.units = "mm"

    for entity in msp:
        layer = entity.dxf.layer
        etype = layer_types.get(layer)

        if etype is None:
            continue

        if etype == "wall":
            if isinstance(entity, Line):
                plan.walls.append(_extract_walls_from_line(entity, layer))
            elif isinstance(entity, LWPolyline):
                plan.walls.extend(_extract_walls_from_polyline(entity, layer))

        elif etype in ("door", "window"):
            if isinstance(entity, Insert):
                plan.openings.append(_extract_opening(entity, layer, etype))

        elif etype == "furniture":
            if isinstance(entity, Insert):
                plan.furniture.append(_extract_furniture(entity, layer))

    plan.compute_bounds()
    return plan
