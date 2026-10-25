"""Geometrie einer Steeldart-Scheibe und Punkteberechnung.

Koordinatensystem: Ursprung im Bull, Einheit Millimeter, x nach rechts, y nach oben.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

# Segmentreihenfolge im Uhrzeigersinn, beginnend oben (20).
SEGMENTS = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

# Radien in mm (offizielle WDF/PDC-Maße, gemessen bis Drahtmitte).
R_BULL = 6.35
R_OUTER_BULL = 15.9
R_TRIPLE_INNER = 99.0
R_TRIPLE_OUTER = 107.0
R_DOUBLE_INNER = 162.0
R_DOUBLE_OUTER = 170.0

# Kalibrierpunkte: Mitte der Außenkante des Doppelrings bei 20, 6, 3 und 11
# (oben, rechts, unten, links). Diese Punkte klickt man bei der Kalibrierung an.
CALIBRATION_POINTS_MM = {
    20: (0.0, R_DOUBLE_OUTER),
    6: (R_DOUBLE_OUTER, 0.0),
    3: (0.0, -R_DOUBLE_OUTER),
    11: (-R_DOUBLE_OUTER, 0.0),
}


@dataclass(frozen=True)
class Hit:
    """Ein getroffenes Feld."""

    segment: int  # 1-20, 25 für Bull, 0 für daneben
    multiplier: int  # 0, 1, 2 oder 3

    @property
    def value(self) -> int:
        return self.segment * self.multiplier

    @property
    def is_double(self) -> bool:
        return self.multiplier == 2

    @property
    def label(self) -> str:
        if self.multiplier == 0:
            return "MISS"
        if self.segment == 25:
            return "BULL" if self.multiplier == 2 else "25"
        prefix = {1: "", 2: "D", 3: "T"}[self.multiplier]
        return f"{prefix}{self.segment}"

    def __str__(self) -> str:
        return self.label


MISS = Hit(0, 0)


def segment_at_angle(x: float, y: float) -> int:
    """Liefert die Segmentzahl (1-20) für eine Position, unabhängig vom Radius."""
    angle = math.degrees(math.atan2(y, x))  # 0° = rechts, gegen Uhrzeigersinn
    clockwise_from_top = (90.0 - angle) % 360.0
    index = int(((clockwise_from_top + 9.0) % 360.0) // 18.0)
    return SEGMENTS[index]


def score(x: float, y: float) -> Hit:
    """Berechnet das getroffene Feld für eine Position in mm."""
    r = math.hypot(x, y)
    if r <= R_BULL:
        return Hit(25, 2)
    if r <= R_OUTER_BULL:
        return Hit(25, 1)
    if r > R_DOUBLE_OUTER:
        return MISS

    segment = segment_at_angle(x, y)
    if R_TRIPLE_INNER < r <= R_TRIPLE_OUTER:
        return Hit(segment, 3)
    if R_DOUBLE_INNER < r <= R_DOUBLE_OUTER:
        return Hit(segment, 2)
    return Hit(segment, 1)


def parse_hit(label: str) -> Hit:
    """Wandelt Eingaben wie 'T20', 'D16', '5', '25', 'BULL', 'MISS' in einen Hit um."""
    s = label.strip().upper()
    if s in ("MISS", "M", "0"):
        return MISS
    if s in ("BULL", "DB", "D25", "50"):
        return Hit(25, 2)
    if s in ("25", "SB", "S25"):
        return Hit(25, 1)

    multiplier = {"S": 1, "D": 2, "T": 3}.get(s[0], 0)
    number = s[1:] if multiplier else s
    multiplier = multiplier or 1
    if not number.isdigit() or not 1 <= int(number) <= 20:
        raise ValueError(f"Ungültiges Feld: {label!r}")
    return Hit(int(number), multiplier)
