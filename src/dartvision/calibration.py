"""Kalibrierung: Abbildung zwischen Kamerabild (Pixel) und Scheibe (mm) per Homographie."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

from .board import CALIBRATION_POINTS_MM, Hit, score


@dataclass
class Calibration:
    # 3x3-Matrix: Bildpunkt (px) -> Scheibenpunkt (mm)
    image_to_board: np.ndarray

    @classmethod
    def from_points(cls, image_points: dict[int, tuple[float, float]]) -> "Calibration":
        """Erstellt die Kalibrierung aus angeklickten Bildpunkten.

        image_points: Segmentnummer (20, 6, 3, 11) -> (x, y) im Bild.
        Weitere Punkte können später in CALIBRATION_POINTS_MM ergänzt werden.
        """
        keys = [k for k in CALIBRATION_POINTS_MM if k in image_points]
        if len(keys) < 4:
            raise ValueError("Mindestens 4 Kalibrierpunkte nötig")
        src = np.array([image_points[k] for k in keys], dtype=np.float32)
        dst = np.array([CALIBRATION_POINTS_MM[k] for k in keys], dtype=np.float32)
        matrix, _ = cv2.findHomography(src, dst)
        if matrix is None:
            raise ValueError("Homographie konnte nicht berechnet werden")
        return cls(matrix)

    @property
    def board_to_image(self) -> np.ndarray:
        return np.linalg.inv(self.image_to_board)

    def to_board(self, x: float, y: float) -> tuple[float, float]:
        pt = cv2.perspectiveTransform(np.array([[[x, y]]], dtype=np.float32), self.image_to_board)
        return float(pt[0, 0, 0]), float(pt[0, 0, 1])

    def to_image(self, x_mm: float, y_mm: float) -> tuple[float, float]:
        pt = cv2.perspectiveTransform(np.array([[[x_mm, y_mm]]], dtype=np.float32), self.board_to_image)
        return float(pt[0, 0, 0]), float(pt[0, 0, 1])

    def score_pixel(self, x: float, y: float) -> Hit:
        return score(*self.to_board(x, y))

    def save(self, path: str | Path) -> None:
        Path(path).write_text(json.dumps({"image_to_board": self.image_to_board.tolist()}, indent=2))

    @classmethod
    def load(cls, path: str | Path) -> "Calibration":
        data = json.loads(Path(path).read_text())
        return cls(np.array(data["image_to_board"], dtype=np.float64))
