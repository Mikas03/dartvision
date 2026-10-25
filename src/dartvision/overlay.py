"""Zeichnet Scheibenraster, Treffer und Spielstand ins Kamerabild."""

from __future__ import annotations

import math

import cv2
import numpy as np

from . import board
from .calibration import Calibration
from .game import X01Game

GREEN = (0, 255, 0)
RED = (0, 0, 255)
YELLOW = (0, 255, 255)
WHITE = (255, 255, 255)


def _ring(calib: Calibration, radius: float, steps: int = 72) -> np.ndarray:
    pts = [
        calib.to_image(radius * math.cos(2 * math.pi * i / steps), radius * math.sin(2 * math.pi * i / steps))
        for i in range(steps)
    ]
    return np.array(pts, dtype=np.int32)


def draw_board(frame: np.ndarray, calib: Calibration) -> None:
    """Projiziert die Ringe und Segmentgrenzen der Scheibe ins Bild (Kalibrierung prüfen)."""
    for r in (board.R_OUTER_BULL, board.R_TRIPLE_INNER, board.R_TRIPLE_OUTER,
              board.R_DOUBLE_INNER, board.R_DOUBLE_OUTER):
        cv2.polylines(frame, [_ring(calib, r)], True, GREEN, 1, cv2.LINE_AA)
    for i in range(20):
        a = math.radians(90 - 9 - 18 * i)
        inner = calib.to_image(board.R_OUTER_BULL * math.cos(a), board.R_OUTER_BULL * math.sin(a))
        outer = calib.to_image(board.R_DOUBLE_OUTER * math.cos(a), board.R_DOUBLE_OUTER * math.sin(a))
        cv2.line(frame, tuple(map(int, inner)), tuple(map(int, outer)), GREEN, 1, cv2.LINE_AA)


def draw_tip(frame: np.ndarray, tip: tuple[float, float], label: str) -> None:
    x, y = map(int, tip)
    cv2.circle(frame, (x, y), 5, RED, -1)
    cv2.putText(frame, label, (x + 8, y - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.6, RED, 2)


def draw_scoreboard(frame: np.ndarray, game: X01Game, message: str = "") -> None:
    y = 25
    for i, p in enumerate(game.players):
        active = i == game.current and not game.winner
        rest = game.remaining_in_turn if active else p.remaining
        text = f"{'>' if active else ' '} {p.name}: {rest}"
        cv2.putText(frame, text, (10, y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, YELLOW if active else WHITE, 2)
        y += 28
    darts = "  ".join(str(h) for h in game.turn)
    cv2.putText(frame, f"Aufnahme: {darts}", (10, y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, WHITE, 1)
    if message:
        cv2.putText(frame, message, (10, y + 28), cv2.FONT_HERSHEY_SIMPLEX, 0.7, RED, 2)
