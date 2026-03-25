from __future__ import annotations
from jinja2 import Environment
from app.dwg.elements import FurnitureItem

# Default placeholder dimensions (mm) for unknown furniture
PLACEHOLDER_SIZES: dict[str, tuple[float, float, float]] = {
    "chair": (500, 500, 800),
    "table": (1200, 800, 750),
    "desk": (1400, 700, 750),
    "sofa": (2000, 900, 850),
    "bed": (2000, 1600, 500),
    "cabinet": (800, 400, 2000),
    "bookshelf": (900, 300, 1800),
}

DEFAULT_SIZE = (600, 600, 750)


def _get_placeholder_size(item: FurnitureItem) -> tuple[float, float, float]:
    if item.component_name:
        name = item.component_name.lower().replace("placeholder_", "")
        for key, size in PLACEHOLDER_SIZES.items():
            if key in name:
                return size
    block = item.block_name.lower()
    for key, size in PLACEHOLDER_SIZES.items():
        if key in block:
            return size
    return DEFAULT_SIZE


def render_furniture(env: Environment, item: FurnitureItem, index: int) -> str:
    w, d, h = _get_placeholder_size(item)
    template = env.get_template("furniture.rb.j2")
    return template.render(
        item=item,
        index=index,
        placeholder_width=w,
        placeholder_depth=d,
        placeholder_height=h,
    )
