from __future__ import annotations

# Extended ACI (AutoCAD Color Index) to hex mapping
ACI_TO_HEX: dict[int, str] = {
    1: "#FF0000", 2: "#FFFF00", 3: "#00FF00", 4: "#00FFFF",
    5: "#0000FF", 6: "#FF00FF", 7: "#FFFFFF", 8: "#808080",
    9: "#C0C0C0", 10: "#FF0000", 11: "#FF7F7F", 12: "#CC0000",
    30: "#FF7F00", 40: "#FF9F00", 50: "#FFBF00",
    60: "#BFFF00", 70: "#7FFF00", 80: "#00FF00",
    90: "#00FF7F", 100: "#00FFBF", 110: "#00FFFF",
    120: "#00BFFF", 130: "#007FFF", 140: "#0000FF",
    150: "#7F00FF", 160: "#BF00FF", 170: "#FF00FF",
}

# Common material names for interior design
MATERIAL_PRESETS: dict[str, dict] = {
    "concrete": {"color": "#B0B0B0", "texture": None},
    "brick": {"color": "#B84C2E", "texture": None},
    "drywall": {"color": "#F5F5F0", "texture": None},
    "wood_floor": {"color": "#C4956A", "texture": None},
    "tile": {"color": "#E8E8E0", "texture": None},
    "glass": {"color": "#C8E8FF", "texture": None},
    "metal": {"color": "#A0A0A8", "texture": None},
}


def aci_to_hex(color_index: int) -> str:
    return ACI_TO_HEX.get(color_index, "#FFFFFF")


def get_material_color(material_name: str | None) -> str:
    if material_name and material_name.lower() in MATERIAL_PRESETS:
        return MATERIAL_PRESETS[material_name.lower()]["color"]
    return "#CCCCCC"
