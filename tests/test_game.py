from dartvision.board import parse_hit
from dartvision.game import X01Game


def throw_all(game: X01Game, *labels: str) -> list[str]:
    return [game.throw(parse_hit(label)) for label in labels]


def test_normal_turn():
    game = X01Game(["A", "B"])
    assert throw_all(game, "T20", "T20", "T20") == ["ok", "ok", "turn_over"]
    assert game.players[0].remaining == 321
    assert game.current_player.name == "B"


def test_bust_over_zero():
    game = X01Game(["A"], start_score=40)
    assert throw_all(game, "T20") == ["bust"]
    assert game.players[0].remaining == 40


def test_bust_on_one_with_double_out():
    game = X01Game(["A"], start_score=21)
    assert throw_all(game, "20") == ["bust"]
    assert game.players[0].remaining == 21


def test_checkout_needs_double():
    game = X01Game(["A"], start_score=40)
    assert throw_all(game, "20", "20") == ["ok", "bust"]
    assert throw_all(game, "D20") == ["win"]
    assert game.winner.name == "A"


def test_single_out():
    game = X01Game(["A"], start_score=20, double_out=False)
    assert throw_all(game, "20") == ["win"]


def test_undo():
    game = X01Game(["A"])
    game.throw(parse_hit("T20"))
    game.undo()
    assert game.remaining_in_turn == 501
