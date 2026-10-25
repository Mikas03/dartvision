from dartvision.board import CALIBRATION_POINTS_MM
from dartvision.evaluate import evaluate_frames
from dartvision.synthetic import Scenario


def test_camera_projects_bull_to_image_center():
    scenario = Scenario(turns=1)
    x, y = scenario.calibration.to_image(0, 0)
    assert abs(x - 640) < 1 and abs(y - 360) < 1
    # 20 liegt oben im Bild, 6 rechts
    assert scenario.calibration.to_image(*CALIBRATION_POINTS_MM[20])[1] < y
    assert scenario.calibration.to_image(*CALIBRATION_POINTS_MM[6])[0] > x


def test_end_to_end_detection():
    scenario = Scenario(turns=2, seed=1, shadows=False)
    frames = list(scenario.frames())
    truth = [{"label": t.label, "tip_mm": t.tip_mm, "frame": t.frame} for t in scenario.truth]

    report = evaluate_frames(frames, truth, scenario.calibration)

    assert len(report.darts) == 6
    assert report.detected == 6
    assert report.correct >= 5
    assert report.false_positives == 0
