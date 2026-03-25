from __future__ import annotations
from dataclasses import dataclass, field
from typing import Literal

Point2D = tuple[float, float]


@dataclass
class Wall:
    start: Point2D
    end: Point2D
    thickness: float = 150.0
    height: float = 2700.0
    material: str | None = None
    color: str | None = None
    layer: str = ""

    @property
    def length(self) -> float:
        dx = self.end[0] - self.start[0]
        dy = self.end[1] - self.start[1]
        return (dx**2 + dy**2) ** 0.5

    @property
    def midpoint(self) -> Point2D:
        return (
            (self.start[0] + self.end[0]) / 2,
            (self.start[1] + self.end[1]) / 2,
        )


@dataclass
class Opening:
    type: Literal["door", "window"]
    position: Point2D
    width: float = 900.0
    height: float = 2100.0
    sill_height: float = 0.0
    rotation: float = 0.0
    wall_index: int | None = None
    swing: str | None = None
    layer: str = ""


@dataclass
class FurnitureItem:
    block_name: str
    position: Point2D
    rotation: float = 0.0
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0)
    component_name: str | None = None
    color: str | None = None
    layer: str = ""


@dataclass
class FloorPlan:
    walls: list[Wall] = field(default_factory=list)
    openings: list[Opening] = field(default_factory=list)
    furniture: list[FurnitureItem] = field(default_factory=list)
    units: str = "mm"
    bounds: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0)
    source_filename: str = ""

    def compute_bounds(self) -> None:
        all_x: list[float] = []
        all_y: list[float] = []
        for w in self.walls:
            all_x.extend([w.start[0], w.end[0]])
            all_y.extend([w.start[1], w.end[1]])
        for o in self.openings:
            all_x.append(o.position[0])
            all_y.append(o.position[1])
        for f in self.furniture:
            all_x.append(f.position[0])
            all_y.append(f.position[1])
        if all_x and all_y:
            self.bounds = (min(all_x), min(all_y), max(all_x), max(all_y))
