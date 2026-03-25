from __future__ import annotations
import math

Point2D = tuple[float, float]

TOLERANCE = 1.0  # 1mm tolerance for point matching


def distance(p1: Point2D, p2: Point2D) -> float:
    return math.hypot(p2[0] - p1[0], p2[1] - p1[1])


def points_equal(p1: Point2D, p2: Point2D, tol: float = TOLERANCE) -> bool:
    return distance(p1, p2) < tol


def point_to_line_distance(point: Point2D, line_start: Point2D, line_end: Point2D) -> float:
    dx = line_end[0] - line_start[0]
    dy = line_end[1] - line_start[1]
    line_len_sq = dx * dx + dy * dy
    if line_len_sq == 0:
        return distance(point, line_start)
    t = max(0, min(1, (
        (point[0] - line_start[0]) * dx + (point[1] - line_start[1]) * dy
    ) / line_len_sq))
    proj_x = line_start[0] + t * dx
    proj_y = line_start[1] + t * dy
    return distance(point, (proj_x, proj_y))


def line_angle(start: Point2D, end: Point2D) -> float:
    return math.atan2(end[1] - start[1], end[0] - start[0])


def are_collinear(
    start1: Point2D, end1: Point2D,
    start2: Point2D, end2: Point2D,
    angle_tol: float = 0.01,
    dist_tol: float = TOLERANCE,
) -> bool:
    a1 = line_angle(start1, end1) % math.pi
    a2 = line_angle(start2, end2) % math.pi
    if abs(a1 - a2) > angle_tol and abs(a1 - a2 - math.pi) > angle_tol:
        return False
    d = point_to_line_distance(start2, start1, end1)
    return d < dist_tol


def offset_point(point: Point2D, angle: float, dist: float) -> Point2D:
    return (
        point[0] + dist * math.cos(angle),
        point[1] + dist * math.sin(angle),
    )


def normal_angle(start: Point2D, end: Point2D) -> float:
    return line_angle(start, end) + math.pi / 2
