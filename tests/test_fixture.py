"""Gemeinsame Testszene mit der App (app/assets/demo_scene, siehe app/test/detector_test.dart).

Beide Implementierungen der Erkennung müssen auf dieser Szene dasselbe Ergebnis liefern.
"""

from pathlib import Path

from dartvision.evaluate import evaluate_fixture

FIXTURE = Path(__file__).parent.parent / "app" / "assets" / "demo_scene"


def test_fixture_matches_app():
    report = evaluate_fixture(FIXTURE)
    assert [d.truth_label for d in report.darts] == ["13", "MISS", "25", "20", "1", "20"]
    assert [d.detected_label for d in report.darts] == ["13", "MISS", "25", "20", "T1", "T5"]
    assert report.false_positives == 0
