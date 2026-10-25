"""Misst die Erkennung gegen bekannte Ergebnisse (z. B. aus synthetic.py)."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

import cv2
import numpy as np

from .board import CALIBRATION_POINTS_MM
from .calibration import Calibration
from .detection import DartDetector, DetectorConfig, Event


@dataclass
class DartResult:
    truth_label: str
    truth_mm: tuple[float, float]
    detected_label: str | None = None
    detected_mm: tuple[float, float] | None = None

    @property
    def correct(self) -> bool:
        return self.detected_label == self.truth_label

    @property
    def error_mm(self) -> float | None:
        if self.detected_mm is None:
            return None
        return math.dist(self.truth_mm, self.detected_mm)


@dataclass
class Report:
    darts: list[DartResult] = field(default_factory=list)
    false_positives: int = 0

    @property
    def detected(self) -> int:
        return sum(d.detected_label is not None for d in self.darts)

    @property
    def correct(self) -> int:
        return sum(d.correct for d in self.darts)

    def summary(self) -> str:
        n = len(self.darts) or 1
        errors = [d.error_mm for d in self.darts if d.error_mm is not None]
        lines = [
            f"Darts:              {len(self.darts)}",
            f"Erkannt:            {self.detected} ({self.detected / n:.0%})",
            f"Richtig gezählt:    {self.correct} ({self.correct / n:.0%})",
            f"Fehlerkennungen:    {self.false_positives}",
        ]
        if errors:
            lines.append(f"Abweichung Spitze:  Median {np.median(errors):.1f} mm, "
                         f"90%-Quantil {np.percentile(errors, 90):.1f} mm")
        return "\n".join(lines)

    def mistakes(self) -> str:
        rows = []
        for i, d in enumerate(self.darts):
            if not d.correct:
                err = f"{d.error_mm:6.1f} mm" if d.error_mm is not None else "      -"
                rows.append(f"  #{i:3d}  echt {d.truth_label:>5}  erkannt {d.detected_label or '-':>5}  {err}")
        return "\n".join(rows) if rows else "  keine"


def evaluate_frames(frames: Iterable[np.ndarray], truth: list[dict], calib: Calibration,
                    config: DetectorConfig | None = None) -> Report:
    detector = DartDetector(config)
    detections: list[tuple[int, tuple[float, float] | None]] = []
    for frame_no, frame in enumerate(frames):
        result = detector.update(frame)
        if result.event is Event.DART:
            detections.append((frame_no, result.tip))

    # Jeder echte Dart bekommt die erste Erkennung zwischen seinem Auftreffen und dem nächsten Dart.
    report = Report()
    used = set()
    for i, t in enumerate(truth):
        result = DartResult(t["label"], tuple(t["tip_mm"]))
        end = truth[i + 1]["frame"] if i + 1 < len(truth) else math.inf
        for j, (frame_no, tip) in enumerate(detections):
            if j not in used and t["frame"] <= frame_no < end:
                used.add(j)
                if tip is not None:
                    result.detected_mm = calib.to_board(*tip)
                    result.detected_label = calib.score_pixel(*tip).label
                break
        report.darts.append(result)
    report.false_positives = len(detections) - len(used)
    return report


def noisy_calibration(true_calib: Calibration, pixels: float, seed: int = 0) -> Calibration:
    """Simuliert ungenaues Anklicken der Kalibrierpunkte."""
    rng = np.random.default_rng(seed)
    points = {}
    for key, mm in CALIBRATION_POINTS_MM.items():
        x, y = true_calib.to_image(*mm)
        points[key] = (x + rng.normal(0, pixels), y + rng.normal(0, pixels))
    return Calibration.from_points(points)


def read_video(path: str | Path) -> Iterable[np.ndarray]:
    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        raise SystemExit(f"Video {path} konnte nicht geöffnet werden")
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        yield frame
    cap.release()


def evaluate_video(video: str | Path, truth_path: str | Path, calib_noise: float = 0.0) -> Report:
    data = json.loads(Path(truth_path).read_text())
    calib = Calibration(np.array(data["image_to_board"]))
    if calib_noise > 0:
        calib = noisy_calibration(calib, calib_noise)
    return evaluate_frames(read_video(video), data["darts"], calib)


def read_fixture(path: str | Path) -> tuple[dict, Iterable[np.ndarray]]:
    """Liest eine mit Scenario.export_fixture erzeugte Szene (Einzelbilder + Wiederholungen)."""
    path = Path(path)
    data = json.loads((path / "scenario.json").read_text())

    def frames() -> Iterable[np.ndarray]:
        for state in data["states"]:
            img = cv2.imread(str(path / state["image"]))
            for _ in range(state["count"]):
                yield img

    return data, frames()


def evaluate_fixture(path: str | Path, config: DetectorConfig | None = None) -> Report:
    data, frames = read_fixture(path)
    w, h = data["width"], data["height"]
    calib_data = data["calibration"]
    calib = Calibration.from_points({
        seg: (x * w, y * h) for seg, (x, y) in zip(calib_data["order"], calib_data["points_normalized"])
    })
    truth = [
        {"frame": d["frame"], "label": d["label"],
         "tip_mm": calib.to_board(d["tip_normalized"][0] * w, d["tip_normalized"][1] * h)}
        for d in data["darts"]
    ]
    return evaluate_frames(frames, truth, calib, config)
