import math

import pytest

from dartvision.board import Hit, MISS, parse_hit, score


def polar(r: float, clockwise_deg_from_top: float) -> tuple[float, float]:
    a = math.radians(90 - clockwise_deg_from_top)
    return r * math.cos(a), r * math.sin(a)


@pytest.mark.parametrize(
    "r, angle, expected",
    [
        (0, 0, "BULL"),
        (10, 45, "25"),
        (50, 0, "20"),
        (103, 0, "T20"),
        (166, 0, "D20"),
        (180, 0, "MISS"),
        (103, 18, "T1"),
        (50, 90, "6"),
        (166, 180, "D3"),
        (103, 270, "T11"),
        (50, 342, "5"),
        (50, 351, "20"),  # knapp links der Mitte von 20
        (50, 8.9, "20"),
        (50, 9.1, "1"),
    ],
)
def test_score(r, angle, expected):
    assert score(*polar(r, angle)).label == expected


def test_values():
    assert Hit(20, 3).value == 60
    assert Hit(25, 2).value == 50
    assert MISS.value == 0


@pytest.mark.parametrize("text, hit", [("T20", Hit(20, 3)), ("d16", Hit(16, 2)), ("5", Hit(5, 1)),
                                       ("bull", Hit(25, 2)), ("25", Hit(25, 1)), ("miss", MISS)])
def test_parse_hit(text, hit):
    assert parse_hit(text) == hit


def test_parse_invalid():
    with pytest.raises(ValueError):
        parse_hit("T21")
