from __future__ import annotations
from datetime import datetime
from pathlib import Path

from jinja2 import Environment, FileSystemLoader

from app.dwg.elements import FloorPlan
from app.sketchup.walls import render_wall
from app.sketchup.openings import render_opening
from app.sketchup.furniture import render_furniture

TEMPLATES_DIR = Path(__file__).parent / "templates"


def generate_ruby_script(plan: FloorPlan) -> str:
    env = Environment(
        loader=FileSystemLoader(str(TEMPLATES_DIR)),
        keep_trailing_newline=True,
    )

    # Collect unique layers
    layers = set()
    for w in plan.walls:
        if w.layer:
            layers.add(w.layer)
    for o in plan.openings:
        if o.layer:
            layers.add(o.layer)
    for f in plan.furniture:
        if f.layer:
            layers.add(f.layer)

    sections: list[str] = []

    # Header
    header_tmpl = env.get_template("header.rb.j2")
    sections.append(header_tmpl.render(
        source_filename=plan.source_filename,
        timestamp=datetime.now().strftime("%Y-%m-%d %H:%M"),
        units=plan.units,
        wall_count=len(plan.walls),
        opening_count=len(plan.openings),
        furniture_count=len(plan.furniture),
        layers=sorted(layers),
    ))

    # Walls
    if plan.walls:
        sections.append("\n# " + "=" * 60)
        sections.append("# WALLS")
        sections.append("# " + "=" * 60)
        for i, wall in enumerate(plan.walls):
            sections.append(render_wall(env, wall, i, plan.units))

    # Openings
    if plan.openings:
        sections.append("\n# " + "=" * 60)
        sections.append("# OPENINGS (Doors & Windows)")
        sections.append("# " + "=" * 60)
        for i, opening in enumerate(plan.openings):
            sections.append(render_opening(env, opening, i))

    # Furniture
    if plan.furniture:
        sections.append("\n# " + "=" * 60)
        sections.append("# FURNITURE")
        sections.append("# " + "=" * 60)
        for i, item in enumerate(plan.furniture):
            sections.append(render_furniture(env, item, i))

    # Footer
    footer_tmpl = env.get_template("footer.rb.j2")
    sections.append(footer_tmpl.render(
        wall_count=len(plan.walls),
        opening_count=len(plan.openings),
        furniture_count=len(plan.furniture),
    ))

    return "\n".join(sections)
