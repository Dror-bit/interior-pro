from __future__ import annotations
import json
from pathlib import Path

from app.dwg.elements import FurnitureItem

MAPPING_FILE = Path(__file__).parent.parent.parent / "component_library" / "mapping.json"


def load_component_mapping() -> dict:
    if MAPPING_FILE.exists():
        with open(MAPPING_FILE) as f:
            return json.load(f)
    return {"doors": {}, "windows": {}, "furniture": {}}


def map_furniture_to_components(items: list[FurnitureItem]) -> list[FurnitureItem]:
    mapping = load_component_mapping()
    furniture_map = mapping.get("furniture", {})

    for item in items:
        name_upper = item.block_name.upper()
        # Try exact match first, then partial match
        if name_upper in furniture_map:
            item.component_name = furniture_map[name_upper]
        else:
            for key, component in furniture_map.items():
                if key in name_upper or name_upper in key:
                    item.component_name = component
                    break
            if item.component_name is None:
                item.component_name = f"placeholder_{item.block_name}"

    return items
