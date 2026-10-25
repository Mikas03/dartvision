"""Synthetische Testvideos mit bekanntem Ergebnis.

Eine Scheibe wird aus der Geometrie in board.py gezeichnet und mit einer virtuellen
Lochkamera schräg aufgenommen. Darts sind einfache 3D-Modelle (Spitze, Barrel, Schaft,
Flight), die aus der Scheibe herausragen und in die Kamera projiziert werden.
Zu jedem Dart wird die echte Einstichstelle gespeichert, damit man die Erkennung messen kann.
"""

from __future__ import annotations

import json
import math
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Iterator

import cv2
import numpy as np

from . import board
from .board import SEGMENTS, score
from .calibration import Calibration

R_SURROUND = 225.0  # schwarzer Rand mit Zahlenring

# Farben (BGR)
BLACK = (35, 35, 35)
CREAM = (190, 220, 232)
RED = (45, 40, 190)
GREEN = (60, 135, 45)
SURROUND = (22, 22, 22)
FLIGHT_COLORS = [(40, 40, 210), (200, 120, 30), (40, 190, 230), (150, 60, 160)]

# Dartaufbau entlang der Achse ab Einstichstelle: (von mm, bis mm, Breite von, Breite bis, Farbe)
DART_PARTS = [
    (0, 28, 2.5, 2.5, (175, 175, 175)),  # Spitze
    (28, 75, 7.0, 7.0, (75, 75, 80)),  # Barrel
    (75, 110, 4.0, 4.0, (50, 50, 50)),  # Schaft
    (110, 122, 6.0, 32.0, None),  # Flight (Farbe je Dart)
    (122, 150, 32.0, 32.0, None),
]


@dataclass
class CameraConfig:
    width: int = 1280
    height: int = 720
    focal: float = 1000.0  # Brennweite in Pixeln
    distance: float = 750.0  # Abstand zum Bull in mm
    yaw: float = 30.0  # seitlicher Winkel in Grad (positiv = Kamera rechts)
    pitch: float = -10.0  # Höhenwinkel in Grad (negativ = Kamera unterhalb)


class Camera:
    """Lochkamera, die auf den Bull schaut. Scheibe liegt in der Ebene z = 0, Werfer bei z > 0."""

    def __init__(self, cfg: CameraConfig) -> None:
        self.cfg = cfg
        yaw, pitch = math.radians(cfg.yaw), math.radians(cfg.pitch)
        self.position = cfg.distance * np.array(
            [math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)]
        )
        forward = -self.position / np.linalg.norm(self.position)
        right = np.cross(forward, [0.0, 1.0, 0.0])
        right /= np.linalg.norm(right)
        down = np.cross(forward, right)
        self.R = np.stack([right, down, forward])
        self.t = -self.R @ self.position
        self.K = np.array([[cfg.focal, 0, cfg.width / 2], [0, cfg.focal, cfg.height / 2], [0, 0, 1]])

    def project(self, points: np.ndarray) -> np.ndarray:
        cam = points @ self.R.T + self.t
        uv = cam @ self.K.T
        return uv[:, :2] / uv[:, 2:3]

    def board_to_image(self) -> np.ndarray:
        """Homographie Scheibe (mm, z = 0) -> Bild (px)."""
        H = self.K @ np.column_stack([self.R[:, 0], self.R[:, 1], self.t])
        return H / H[2, 2]


def render_board_topdown(size: int = 1600) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Zeichnet die Scheibe von vorne. Gibt Bild, Maske und Matrix Pixel -> mm zurück."""
    scale = size / 2 / R_SURROUND
    v, u = np.mgrid[0:size, 0:size].astype(np.float32)
    x = (u - size / 2) / scale
    y = (size / 2 - v) / scale
    r = np.hypot(x, y)
    clockwise = (90.0 - np.degrees(np.arctan2(y, x))) % 360.0
    even = (((clockwise + 9.0) % 360.0) // 18.0).astype(int) % 2 == 0

    img = np.zeros((size, size, 3), np.uint8)
    img[:] = SURROUND
    img[even & (r <= board.R_DOUBLE_OUTER)] = BLACK
    img[~even & (r <= board.R_DOUBLE_OUTER)] = CREAM
    rings = ((r > board.R_TRIPLE_INNER) & (r <= board.R_TRIPLE_OUTER)) | (
        (r > board.R_DOUBLE_INNER) & (r <= board.R_DOUBLE_OUTER)
    )
    img[rings & even] = RED
    img[rings & ~even] = GREEN
    img[r <= board.R_OUTER_BULL] = GREEN
    img[r <= board.R_BULL] = RED

    for i, number in enumerate(SEGMENTS):
        a = math.radians(90 - 18 * i)
        cx = size / 2 + 197 * scale * math.cos(a)
        cy = size / 2 - 197 * scale * math.sin(a)
        text = str(number)
        (tw, th), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 1.6, 3)
        cv2.putText(img, text, (int(cx - tw / 2), int(cy + th / 2)), cv2.FONT_HERSHEY_SIMPLEX,
                    1.6, (230, 230, 230), 3, cv2.LINE_AA)

    mask = (r <= R_SURROUND).astype(np.uint8) * 255
    px_to_mm = np.array([[1 / scale, 0, -size / 2 / scale], [0, -1 / scale, size / 2 / scale], [0, 0, 1]])
    return img, mask, px_to_mm


@dataclass
class Dart:
    tip_mm: tuple[float, float]
    direction: tuple[float, float, float]  # Einheitsvektor aus der Scheibe heraus (z > 0)
    color: tuple[int, int, int]
    height: float = 0.0  # > 0: Dart fliegt noch, so viele mm vor der Scheibe


class SceneRenderer:
    def __init__(self, camera: Camera, shadows: bool = True,
                 light_dir: tuple[float, float, float] = (0.1, 0.35, 1.0)) -> None:
        self.camera = camera
        self.shadows = shadows
        light = np.array(light_dir, dtype=float)
        self.light = light / np.linalg.norm(light)

        w, h = camera.cfg.width, camera.cfg.height
        top, mask, px_to_mm = render_board_topdown()
        H = camera.board_to_image() @ px_to_mm
        warped = cv2.warpPerspective(top, H, (w, h), flags=cv2.INTER_AREA)
        warped_mask = cv2.warpPerspective(mask, H, (w, h), flags=cv2.INTER_LINEAR)

        # Wand mit leichtem Helligkeitsverlauf
        gradient = np.linspace(125, 95, h, dtype=np.float32)[:, None, None]
        wall = np.repeat(np.repeat(gradient, w, axis=1), 3, axis=2)
        alpha = (warped_mask.astype(np.float32) / 255)[..., None]
        self.background = (warped * alpha + wall * (1 - alpha)).astype(np.uint8)

    def render(self, darts: list[Dart], occluder: tuple[tuple[int, int], tuple[int, int]] | None = None) -> np.ndarray:
        frame = self.background.copy()
        if self.shadows:
            self._draw_shadows(frame, darts)
        # weiter entfernte Darts zuerst zeichnen, damit nähere sie verdecken
        cam = self.camera.position
        for dart in sorted(darts, key=lambda d: -np.linalg.norm(self._tip3d(d) - cam)):
            for poly, color in self._dart_polygons(dart):
                cv2.fillConvexPoly(frame, self.camera.project(poly).astype(np.int32), color, cv2.LINE_AA)
        if occluder:
            center, axes = occluder
            cv2.ellipse(frame, center, axes, 0, 0, 360, (120, 150, 200), -1, cv2.LINE_AA)
        return frame

    @staticmethod
    def _tip3d(dart: Dart) -> np.ndarray:
        return np.array([dart.tip_mm[0], dart.tip_mm[1], 0.0]) + np.array(dart.direction) * dart.height

    def _dart_polygons(self, dart: Dart) -> Iterator[tuple[np.ndarray, tuple[int, int, int]]]:
        tip = self._tip3d(dart)
        axis = np.array(dart.direction)
        side = np.cross(axis, self.camera.position - tip)  # quer zur Blickrichtung
        side /= np.linalg.norm(side)
        for start, end, w0, w1, color in DART_PARTS:
            p0, p1 = tip + axis * start, tip + axis * end
            poly = np.array([p0 - side * w0 / 2, p1 - side * w1 / 2, p1 + side * w1 / 2, p0 + side * w0 / 2])
            yield poly, color or dart.color

    def _draw_shadows(self, frame: np.ndarray, darts: list[Dart]) -> None:
        shadow = np.zeros(frame.shape[:2], np.uint8)
        for dart in darts:
            for poly, _ in self._dart_polygons(dart):
                on_board = poly - self.light * (poly[:, 2:3] / self.light[2])  # entlang Licht auf z = 0
                cv2.fillConvexPoly(shadow, self.camera.project(on_board).astype(np.int32), 255, cv2.LINE_AA)
        shadow = cv2.GaussianBlur(shadow, (15, 15), 0).astype(np.float32) / 255 * 0.3
        frame[:] = (frame * (1 - shadow[..., None])).astype(np.uint8)


@dataclass
class TruthDart:
    turn: int
    index: int
    frame: int  # erstes Bild, in dem der Dart steckt
    tip_mm: tuple[float, float]
    tip_px: tuple[float, float]
    label: str


@dataclass
class Scenario:
    """Erzeugt eine Bildfolge: pro Aufnahme 3 Würfe, danach werden die Darts gezogen."""

    turns: int = 10
    seed: int = 0
    camera: CameraConfig = field(default_factory=CameraConfig)
    shadows: bool = True
    noise: float = 2.0  # Bildrauschen (Standardabweichung in Grauwerten)
    hold_frames: int = 25  # so lange steckt ein Dart, bevor der nächste kommt
    truth: list[TruthDart] = field(init=False, default_factory=list)

    def __post_init__(self) -> None:
        self.cam = Camera(self.camera)
        self.renderer = SceneRenderer(self.cam, shadows=self.shadows)
        self.calibration = Calibration(np.linalg.inv(self.cam.board_to_image()))
        self.rng = np.random.default_rng(self.seed)
        # Vorberechnetes Rauschen, zufällig gewählt pro Bild (deutlich schneller als jedes Mal neu)
        shape = (self.camera.height, self.camera.width, 3)
        self._noise_bank = [self.rng.normal(0, self.noise, shape).astype(np.int16) for _ in range(8)]

    def frames(self) -> Iterator[np.ndarray]:
        self.truth = []
        frame_no = 0

        def emit(img: np.ndarray, count: int = 1) -> Iterator[np.ndarray]:
            nonlocal frame_no
            for _ in range(count):
                yield self._add_noise(img)
                frame_no += 1

        yield from emit(self.renderer.render([]), 30)
        for turn in range(self.turns):
            color = FLIGHT_COLORS[turn % len(FLIGHT_COLORS)]
            darts: list[Dart] = []
            for index in range(3):
                dart = self._random_dart(color)
                for height in (900, 550, 280, 90):  # Dart im Anflug
                    flying = Dart(dart.tip_mm, dart.direction, dart.color, height)
                    yield from emit(self.renderer.render(darts + [flying]))
                darts.append(dart)
                tip_px = self.calibration.to_image(*dart.tip_mm)
                self.truth.append(TruthDart(turn, index, frame_no, dart.tip_mm, tip_px, score(*dart.tip_mm).label))
                yield from emit(self.renderer.render(darts), self.hold_frames)

            yield from emit(self.renderer.render(darts), 15)
            yield from self._pull_darts(darts, emit)
            yield from emit(self.renderer.render([]), 30)

    def _pull_darts(self, darts: list[Dart], emit) -> Iterator[np.ndarray]:
        """Eine 'Hand' kommt ins Bild, die Darts verschwinden, die Hand geht wieder."""
        target = np.mean([self.calibration.to_image(*d.tip_mm) for d in darts], axis=0)
        start = np.array([self.camera.width + 200, target[1] + 150])
        axes = (170, 120)
        steps = 10
        for i in range(steps):
            pos = start + (target - start) * (i + 1) / steps
            yield from emit(self.renderer.render(darts, (tuple(map(int, pos)), axes)))
        yield from emit(self.renderer.render([], (tuple(map(int, target)), axes)), 8)
        for i in range(steps):
            pos = target + (start - target) * (i + 1) / steps
            yield from emit(self.renderer.render([], (tuple(map(int, pos)), axes)))

    def _random_dart(self, color: tuple[int, int, int]) -> Dart:
        roll = self.rng.random()
        if roll < 0.6:  # auf T20 gezielt
            x, y = self.rng.normal(0, 18), self.rng.normal(103, 18)
        elif roll < 0.9:  # irgendwo auf der Scheibe
            r, a = 170 * math.sqrt(self.rng.random()), self.rng.uniform(0, 2 * math.pi)
            x, y = r * math.cos(a), r * math.sin(a)
        else:  # knapp daneben, steckt im Rand
            r, a = self.rng.uniform(172, 210), self.rng.uniform(0, 2 * math.pi)
            x, y = r * math.cos(a), r * math.sin(a)
        # Darts stecken nicht gerade, sondern leicht schräg
        tilt_x = math.tan(math.radians(self.rng.normal(0, 8)))
        tilt_y = math.tan(math.radians(self.rng.normal(5, 8)))
        d = np.array([tilt_x, tilt_y, 1.0])
        d /= np.linalg.norm(d)
        return Dart((float(x), float(y)), tuple(d.tolist()), color)

    def _add_noise(self, img: np.ndarray) -> np.ndarray:
        if self.noise <= 0:
            return img
        noise = self._noise_bank[self.rng.integers(len(self._noise_bank))]
        return np.clip(img.astype(np.int16) + noise, 0, 255).astype(np.uint8)

    def save(self, video_path: str | Path, fps: int = 30) -> tuple[Path, Path]:
        """Schreibt Video, Ground Truth (*.truth.json) und Kalibrierung (*.calibration.json)."""
        video_path = Path(video_path)
        video_path.parent.mkdir(parents=True, exist_ok=True)
        writer = cv2.VideoWriter(str(video_path), cv2.VideoWriter_fourcc(*"mp4v"), fps,
                                 (self.camera.width, self.camera.height))
        for frame in self.frames():
            writer.write(frame)
        writer.release()

        truth_path = video_path.with_suffix(".truth.json")
        truth_path.write_text(json.dumps({
            "camera": asdict(self.camera),
            "image_to_board": self.calibration.image_to_board.tolist(),
            "darts": [asdict(d) for d in self.truth],
        }, indent=2))
        self.calibration.save(video_path.with_suffix(".calibration.json"))
        return video_path, truth_path
