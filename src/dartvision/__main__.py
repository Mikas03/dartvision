"""Kommandozeile.

    python -m dartvision calibrate --source 0
    python -m dartvision play --source 0 --players Anna Ben
    python -m dartvision play --source data/videos/synth.mp4 --calibration data/videos/synth.calibration.json
    python -m dartvision synth --out data/videos/synth.mp4
    python -m dartvision evaluate --video data/videos/synth.mp4
"""

from __future__ import annotations

import argparse
from pathlib import Path

import cv2

from .board import CALIBRATION_POINTS_MM
from .calibration import Calibration
from .detection import DartDetector, Event
from .game import X01Game
from .overlay import draw_board, draw_scoreboard, draw_tip

WINDOW = "dartvision"


def open_source(source: str) -> cv2.VideoCapture:
    cap = cv2.VideoCapture(int(source) if source.isdigit() else source)
    if not cap.isOpened():
        raise SystemExit(f"Videoquelle {source!r} konnte nicht geöffnet werden")
    return cap


def calibrate(args: argparse.Namespace) -> None:
    """Zeigt ein Standbild; man klickt die Außenkante des Doppelrings bei 20, 6, 3, 11."""
    cap = open_source(args.source)
    ok, frame = cap.read()
    cap.release()
    if not ok:
        raise SystemExit("Kein Bild von der Kamera erhalten")

    order = list(CALIBRATION_POINTS_MM)
    clicked: dict[int, tuple[float, float]] = {}

    def on_mouse(event, x, y, *_):
        if event == cv2.EVENT_LBUTTONDOWN and len(clicked) < len(order):
            clicked[order[len(clicked)]] = (x, y)

    cv2.namedWindow(WINDOW)
    cv2.setMouseCallback(WINDOW, on_mouse)
    while True:
        view = frame.copy()
        for x, y in clicked.values():
            cv2.circle(view, (int(x), int(y)), 4, (0, 0, 255), -1)
        if len(clicked) < len(order):
            hint = f"Klicke Doppelring-Aussenkante Mitte bei {order[len(clicked)]}  (r = neu, q = Abbruch)"
        else:
            calib = Calibration.from_points(clicked)
            draw_board(view, calib)
            hint = "Passt das Raster? s = speichern, r = neu, q = Abbruch"
        cv2.putText(view, hint, (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
        cv2.imshow(WINDOW, view)

        key = cv2.waitKey(30) & 0xFF
        if key == ord("q"):
            break
        if key == ord("r"):
            clicked.clear()
        if key == ord("s") and len(clicked) == len(order):
            calib.save(args.out)
            print(f"Kalibrierung gespeichert: {args.out}")
            break
    cv2.destroyAllWindows()


def play(args: argparse.Namespace) -> None:
    calib = Calibration.load(args.calibration)
    game = X01Game(args.players, start_score=args.start, double_out=not args.single_out)
    detector = DartDetector()
    cap = open_source(args.source)
    tips: list[tuple[tuple[float, float], str]] = []
    message = ""
    # Videodateien in Originalgeschwindigkeit abspielen, Kamera so schnell wie möglich
    is_file = not args.source.isdigit()
    delay = max(1, int(1000 / (cap.get(cv2.CAP_PROP_FPS) or 30))) if is_file else 1
    paused = False

    def register(tip: tuple[float, float]) -> None:
        nonlocal message
        hit = calib.score_pixel(*tip)
        tips.append((tip, str(hit)))
        result = game.throw(hit)
        if result == "win":
            message = f"{game.winner.name} gewinnt!"
        else:
            message = {"bust": "BUST!", "turn_over": "Darts ziehen"}.get(result, "")
        print(f"{hit}  -> {result}")

    def on_mouse(event, x, y, *_):
        # Manuelle Eingabe / Korrektur: Klick auf die Stelle, wo der Dart steckt
        if event == cv2.EVENT_LBUTTONDOWN and not game.winner:
            register((x, y))

    cv2.namedWindow(WINDOW)
    cv2.setMouseCallback(WINDOW, on_mouse)
    while True:
        if paused:
            key = cv2.waitKey(50) & 0xFF
            if key == ord(" "):
                paused = False
            elif key == ord("q"):
                break
            continue

        ok, frame = cap.read()
        if not ok:
            print("Video zu Ende – beliebige Taste zum Schließen")
            cv2.waitKey(0)
            break

        detection = detector.update(frame)
        if detection.event is Event.DART and detection.tip and not game.winner:
            register(detection.tip)
        elif detection.event is Event.BOARD_CLEARED:
            tips.clear()
            message = ""

        view = frame.copy()
        if args.grid:
            draw_board(view, calib)
        for tip, label in tips:
            draw_tip(view, tip, label)
        draw_scoreboard(view, game, message)
        cv2.imshow(WINDOW, view)

        key = cv2.waitKey(delay) & 0xFF
        if key == ord("q"):
            break
        if key == ord(" "):
            paused = True
        if key == ord("u") and game.turn:  # letzten Dart zurücknehmen
            game.undo()
            if tips:
                tips.pop()
        if key == ord("n"):  # Aufnahme beenden
            game.next_player()
        if key == ord("r"):  # Scheibe ist leer -> neues Referenzbild
            detector.reset(frame, empty=True)
            tips.clear()
        if key == ord("g"):
            args.grid = not args.grid

    cap.release()
    cv2.destroyAllWindows()


def synth(args: argparse.Namespace) -> None:
    from .synthetic import CameraConfig, Scenario

    camera = CameraConfig(yaw=args.yaw, pitch=args.pitch, distance=args.distance)
    scenario = Scenario(turns=args.turns, seed=args.seed, camera=camera,
                        shadows=not args.no_shadows, noise=args.noise)
    video, truth = scenario.save(args.out)
    print(f"Video:        {video}")
    print(f"Ergebnisse:   {truth}")
    print(f"Kalibrierung: {video.with_suffix('.calibration.json')}")


def evaluate(args: argparse.Namespace) -> None:
    from .evaluate import evaluate_video

    truth = args.truth or Path(args.video).with_suffix(".truth.json")
    report = evaluate_video(args.video, truth, calib_noise=args.calib_noise)
    print(report.summary())
    print("Falsch gezählt:")
    print(report.mistakes())


def main() -> None:
    parser = argparse.ArgumentParser(prog="dartvision")
    sub = parser.add_subparsers(dest="command", required=True)

    p_cal = sub.add_parser("calibrate", help="Kamera auf die Scheibe kalibrieren")
    p_cal.add_argument("--source", default="0", help="Kameraindex oder Videodatei")
    p_cal.add_argument("--out", default="calibration.json")
    p_cal.set_defaults(func=calibrate)

    p_play = sub.add_parser("play", help="X01 spielen mit automatischer Erkennung")
    p_play.add_argument("--source", default="0", help="Kameraindex oder Videodatei")
    p_play.add_argument("--calibration", default="calibration.json")
    p_play.add_argument("--players", nargs="+", default=["Spieler 1"])
    p_play.add_argument("--start", type=int, default=501)
    p_play.add_argument("--single-out", action="store_true")
    p_play.add_argument("--grid", action="store_true", help="Scheibenraster einblenden")
    p_play.set_defaults(func=play)

    p_syn = sub.add_parser("synth", help="Synthetisches Testvideo mit bekannten Ergebnissen erzeugen")
    p_syn.add_argument("--out", default="data/videos/synth.mp4")
    p_syn.add_argument("--turns", type=int, default=10, help="Anzahl Aufnahmen à 3 Darts")
    p_syn.add_argument("--seed", type=int, default=0)
    p_syn.add_argument("--yaw", type=float, default=30.0, help="seitlicher Kamerawinkel in Grad")
    p_syn.add_argument("--pitch", type=float, default=-10.0, help="Höhenwinkel in Grad")
    p_syn.add_argument("--distance", type=float, default=750.0, help="Abstand Kamera-Bull in mm")
    p_syn.add_argument("--noise", type=float, default=2.0, help="Bildrauschen")
    p_syn.add_argument("--no-shadows", action="store_true")
    p_syn.set_defaults(func=synth)

    p_eval = sub.add_parser("evaluate", help="Erkennung gegen bekannte Ergebnisse messen")
    p_eval.add_argument("--video", required=True)
    p_eval.add_argument("--truth", help="Standard: <video>.truth.json")
    p_eval.add_argument("--calib-noise", type=float, default=0.0,
                        help="Klick-Ungenauigkeit der Kalibrierung in Pixeln simulieren")
    p_eval.set_defaults(func=evaluate)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
