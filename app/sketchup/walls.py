from __future__ import annotations
from jinja2 import Environment
from app.dwg.elements import Wall


def render_wall(env: Environment, wall: Wall, index: int, units: str) -> str:
    template = env.get_template("wall.rb.j2")
    return template.render(wall=wall, index=index, units=units)
