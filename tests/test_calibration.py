import numpy as np

from dartvision.calibration import Calibration
from dartvision.detection import DartDetector


def test_calibration_roundtrip():
    # Scheibe frontal: Mittelpunkt (400, 300), 1 mm = 1.5 px, Bild-y zeigt nach unten
    points = {20: (400, 45), 6: (655, 300), 3: (400, 555), 11: (145, 300)}
    calib = Calibration.from_points(points)

    assert calib.score_pixel(400, 300).label == "BULL"
    assert calib.score_pixel(400, 300 - 103 * 1.5).label == "T20"
    assert calib.score_pixel(400 + 166 * 1.5, 300).label == "D6"

    x, y = calib.to_image(*calib.to_board(123, 234))
    assert abs(x - 123) < 1e-3 and abs(y - 234) < 1e-3


def test_find_tip_picks_narrow_end():
    # Künstlicher "Dart": schmaler Schaft links, breiter Flight rechts
    mask = np.zeros((200, 300), dtype=np.uint8)
    mask[98:102, 50:200] = 255
    mask[85:115, 200:250] = 255
    tip = DartDetector().find_tip(mask)
    assert tip is not None
    assert abs(tip[0] - 50) < 5 and abs(tip[1] - 100) < 5
