from __future__ import annotations

from app.dwg.elements import Opening, Wall
from app.geometry.utils import point_to_line_distance


def associate_openings_with_walls(
    openings: list[Opening],
    walls: list[Wall],
    max_distance: float = 500.0,
) -> list[Opening]:
    for opening in openings:
        best_wall_idx = None
        best_dist = max_distance

        for idx, wall in enumerate(walls):
            d = point_to_line_distance(opening.position, wall.start, wall.end)
            if d < best_dist:
                best_dist = d
                best_wall_idx = idx

        opening.wall_index = best_wall_idx

    return openings
