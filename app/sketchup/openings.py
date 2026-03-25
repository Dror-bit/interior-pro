from __future__ import annotations
from jinja2 import Environment
from app.dwg.elements import Opening


def render_opening(env: Environment, opening: Opening, index: int) -> str:
    template = env.get_template("opening.rb.j2")
    return template.render(opening=opening, index=index)
