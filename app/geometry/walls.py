from __future__ import annotations
import math

from app.dwg.elements import Wall
from app.geometry.utils import are_collinear, distance, line_angle, points_equal


def merge_collinear_walls(walls: list[Wall], tolerance: float = 1.0) -> list[Wall]:
    if not walls:
        return []

    merged = list(walls)
    changed = True

    while changed:
        changed = False
        new_merged = []
        used = set()

        for i in range(len(merged)):
            if i in used:
                continue
            current = merged[i]
            for j in range(i + 1, len(merged)):
                if j in used:
                    continue
                other = merged[j]
                if abs(current.thickness - other.thickness) > tolerance:
                    continue
                if not are_collinear(
                    current.start, current.end, other.start, other.end, dist_tol=tolerance
                ):
                    continue
                # Check if segments share an endpoint (can be merged)
                if points_equal(current.end, other.start, tolerance):
                    current = Wall(
                        start=current.start, end=other.end,
                        thickness=current.thickness, height=current.height,
                        material=current.material, color=current.color,
                        layer=current.layer,
                    )
                    used.add(j)
                    changed = True
                elif points_equal(other.end, current.start, tolerance):
                    current = Wall(
                        start=other.start, end=current.end,
                        thickness=current.thickness, height=current.height,
                        material=current.material, color=current.color,
                        layer=current.layer,
                    )
                    used.add(j)
                    changed = True

            new_merged.append(current)
            used.add(i)

        merged = new_merged

    return merged


def detect_wall_thickness(walls: list[Wall], max_thickness: float = 500.0) -> list[Wall]:
    """Detect wall thickness from parallel line pairs."""
    if len(walls) < 2:
        return walls

    paired = set()
    result = []

    for i in range(len(walls)):
        if i in paired:
            continue
        best_j = None
        best_dist = max_thickness

        for j in range(i + 1, len(walls)):
            if j in paired:
                continue
            # Check if parallel (same angle)
            a1 = line_angle(walls[i].start, walls[i].end) % math.pi
            a2 = line_angle(walls[j].start, walls[j].end) % math.pi
            if abs(a1 - a2) > 0.01 and abs(a1 - a2 - math.pi) > 0.01:
                continue

            # Check distance between parallel lines
            mid_i = walls[i].midpoint
            from app.geometry.utils import point_to_line_distance
            d = point_to_line_distance(mid_i, walls[j].start, walls[j].end)
            if d < best_dist and d > 1.0:
                best_dist = d
                best_j = j

        if best_j is not None and best_dist <= max_thickness:
            # Create a single wall at the centerline with detected thickness
            w1, w2 = walls[i], walls[best_j]
            center_start = (
                (w1.start[0] + w2.start[0]) / 2,
                (w1.start[1] + w2.start[1]) / 2,
            )
            center_end = (
                (w1.end[0] + w2.end[0]) / 2,
                (w1.end[1] + w2.end[1]) / 2,
            )
            result.append(Wall(
                start=center_start, end=center_end,
                thickness=best_dist, height=w1.height,
                material=w1.material, color=w1.color, layer=w1.layer,
            ))
            paired.add(i)
            paired.add(best_j)
        else:
            result.append(walls[i])

    return result
