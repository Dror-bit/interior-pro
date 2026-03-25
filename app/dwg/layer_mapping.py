from __future__ import annotations
import re
from typing import Literal

ElementType = Literal["wall", "door", "window", "furniture", "ignore"]

DEFAULT_PATTERNS: dict[ElementType, list[str]] = {
    "wall": [
        r"(?i).*wall.*",
        r"(?i)^A-WALL.*",
        r"(?i).*קיר.*",
    ],
    "door": [
        r"(?i).*door.*",
        r"(?i)^A-DOOR.*",
        r"(?i).*דלת.*",
    ],
    "window": [
        r"(?i).*wind.*",
        r"(?i)^A-GLAZ.*",
        r"(?i).*חלון.*",
    ],
    "furniture": [
        r"(?i).*furn.*",
        r"(?i)^A-FURN.*",
        r"(?i).*רהיט.*",
        r"(?i).*equip.*",
    ],
}


class LayerMapper:
    def __init__(self, custom_mapping: dict[str, ElementType] | None = None):
        self._exact: dict[str, ElementType] = custom_mapping or {}
        self._compiled: dict[ElementType, list[re.Pattern]] = {
            etype: [re.compile(p) for p in patterns]
            for etype, patterns in DEFAULT_PATTERNS.items()
        }

    def classify(self, layer_name: str) -> ElementType | None:
        if layer_name in self._exact:
            return self._exact[layer_name]
        for etype, patterns in self._compiled.items():
            for pattern in patterns:
                if pattern.match(layer_name):
                    return etype
        return None

    def classify_layers(self, layer_names: list[str]) -> dict[str, ElementType | None]:
        return {name: self.classify(name) for name in layer_names}
