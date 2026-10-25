"""Klassische Darterkennung per Differenzbild.

Ablauf:
1. Referenzbild der Scheibe merken (ohne neue Darts).
2. Jedes Kamerabild mit dem vorherigen vergleichen: erst wenn das Bild wieder ruhig ist
   (keine Bewegung mehr), wird es mit der Referenz verglichen.
3. Kleine bis mittlere Änderung -> neuer Dart. Spitze bestimmen, Referenz aktualisieren.
4. Sieht das Bild wieder aus wie die leere Scheibe -> Darts wurden gezogen.
5. Sehr große Änderung -> Person/Hand steht im Bild -> ignorieren.

Das ist ein Startpunkt. Für bessere Ergebnisse kann man diesen Teil später
durch ein ML-Modell (z. B. YOLO-Keypoints wie bei DeepDarts) ersetzen.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto

import cv2
import numpy as np


@dataclass
class DetectorConfig:
    blur_kernel: int = 5
    diff_threshold: int = 30  # Farbunterschied (größter Kanal), ab dem ein Pixel als geändert gilt
    motion_pixels: int = 500  # mehr geänderte Pixel zum Vorbild = Bewegung
    stable_frames: int = 8  # so viele ruhige Bilder hintereinander, bevor ausgewertet wird
    min_dart_area: int = 300  # kleinere Änderungen ignorieren (Rauschen)
    max_dart_area: int = 30_000  # größere Änderungen = Hand / Person / Darts ziehen
    # Die Flächenwerte gelten für diese Bildgröße und werden für andere Auflösungen skaliert
    reference_pixels: int = 1280 * 720
    end_fraction: float = 0.15  # Anteil der Dartlänge, der zur Breitenmessung genutzt wird
    remove_shadows: bool = True
    shadow_min_ratio: float = 0.45  # Schatten machen höchstens so viel dunkler ...
    shadow_max_ratio: float = 0.92  # ... und mindestens so viel
    shadow_max_spread: float = 0.08  # Kanäle dürfen sich so stark unterscheiden (Farbe bleibt gleich)


class Event(Enum):
    NONE = auto()
    DART = auto()
    BOARD_CLEARED = auto()


@dataclass
class Detection:
    event: Event
    tip: tuple[float, float] | None = None
    mask: np.ndarray | None = None


class DartDetector:
    def __init__(self, config: DetectorConfig | None = None) -> None:
        self.config = config or DetectorConfig()
        self.reference: np.ndarray | None = None  # Stand nach dem letzten erkannten Dart
        self.empty: np.ndarray | None = None  # leere Scheibe
        self.previous: np.ndarray | None = None
        self.stable_count = 0
        self.darts_on_board = 0
        self.area_scale = 1.0

    def reset(self, frame: np.ndarray, empty: bool = False) -> None:
        """Setzt das aktuelle Bild als Referenz; mit empty=True auch als leere Scheibe."""
        img = self._prepare(frame)
        self.area_scale = img.shape[0] * img.shape[1] / self.config.reference_pixels
        self.reference = img
        self.previous = img
        self.stable_count = 0
        if empty or self.empty is None:
            self.empty = img
            self.darts_on_board = 0

    def update(self, frame: np.ndarray) -> Detection:
        img = self._prepare(frame)
        if self.reference is None or self.previous is None:
            self.reset(frame, empty=True)
            return Detection(Event.NONE)

        cfg, scale = self.config, self.area_scale
        moving = np.count_nonzero(self._diff(img, self.previous)) > cfg.motion_pixels * scale
        self.previous = img
        self.stable_count = 0 if moving else self.stable_count + 1
        if self.stable_count != self.config.stable_frames:
            return Detection(Event.NONE)

        # Bild ist gerade ruhig geworden. Sieht es wieder wie die leere Scheibe aus,
        # wurden die Darts gezogen.
        if self.darts_on_board and np.count_nonzero(self._dart_mask(img, self.empty)) < cfg.min_dart_area * scale:
            self.reference = img
            self.darts_on_board = 0
            return Detection(Event.BOARD_CLEARED)

        mask = self._dart_mask(img, self.reference)
        changed = np.count_nonzero(mask)
        if changed < cfg.min_dart_area * scale:
            return Detection(Event.NONE)
        if changed > cfg.max_dart_area * scale:
            # Person/Hand steht im Bild -> ignorieren, Referenz bleibt
            return Detection(Event.NONE, mask=mask)

        tip = self.find_tip(mask)
        self.reference = img
        self.darts_on_board += 1
        return Detection(Event.DART, tip=tip, mask=mask)

    def find_tip(self, mask: np.ndarray) -> tuple[float, float] | None:
        """Schätzt die Dartspitze in einer Differenzmaske.

        Idee: Hauptachse aller geänderten Pixel bestimmen. Das Ende, an dem die Maske
        schmaler ist, ist die Spitze; das breite Ende ist der Flight.
        Bewusst alle Pixel statt nur der größten Kontur: Ein dunkler Schaft auf einem
        schwarzen Segment fällt im Differenzbild weg, der Dart zerfällt dann in Teile.
        """
        ys, xs = np.nonzero(mask)
        if len(xs) < 5:
            return None
        points = np.column_stack([xs, ys]).astype(np.float32)

        vx, vy, cx, cy = cv2.fitLine(points, cv2.DIST_L2, 0, 0.01, 0.01).flatten()
        axis = np.array([vx, vy])
        normal = np.array([-vy, vx])
        rel = points - np.array([cx, cy])
        along = rel @ axis
        across = rel @ normal

        lo, hi = along.min(), along.max()
        span = (hi - lo) * self.config.end_fraction
        width_lo = np.ptp(across[along < lo + span]) if np.any(along < lo + span) else np.inf
        width_hi = np.ptp(across[along > hi - span]) if np.any(along > hi - span) else np.inf

        # äußerster Pixel am schmalen Ende (robuster als ein Punkt auf der Achse,
        # die durch den breiten Flight leicht schief liegen kann)
        tip = points[np.argmin(along) if width_lo < width_hi else np.argmax(along)]
        return float(tip[0]), float(tip[1])

    def _prepare(self, frame: np.ndarray) -> np.ndarray:
        if frame.ndim == 2:
            frame = cv2.cvtColor(frame, cv2.COLOR_GRAY2BGR)
        k = self.config.blur_kernel
        return cv2.GaussianBlur(frame, (k, k), 0)

    def _diff(self, a: np.ndarray, b: np.ndarray) -> np.ndarray:
        """Maske der Pixel, die sich in mindestens einem Farbkanal deutlich geändert haben."""
        diff = cv2.absdiff(a, b).max(axis=2)
        _, mask = cv2.threshold(diff, self.config.diff_threshold, 255, cv2.THRESH_BINARY)
        return mask

    def _shadow(self, current: np.ndarray, reference: np.ndarray) -> np.ndarray:
        """Pixel, die nur gleichmäßig dunkler geworden sind (gleiche Farbe) -> wahrscheinlich Schatten."""
        ratio = (current.astype(np.float32) + 1) / (reference.astype(np.float32) + 1)
        mean = ratio.mean(axis=2)
        spread = ratio.max(axis=2) - ratio.min(axis=2)
        cfg = self.config
        return (mean > cfg.shadow_min_ratio) & (mean < cfg.shadow_max_ratio) & (spread < cfg.shadow_max_spread)

    def _dart_mask(self, current: np.ndarray, reference: np.ndarray) -> np.ndarray:
        mask = self._diff(current, reference)
        if self.config.remove_shadows:
            mask[self._shadow(current, reference)] = 0
        return self._clean(mask)

    @staticmethod
    def _clean(mask: np.ndarray) -> np.ndarray:
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
        return cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)
