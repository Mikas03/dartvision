"""Spiellogik für X01 (301, 501, ...) mit Double-Out."""

from __future__ import annotations

from dataclasses import dataclass, field

from .board import Hit

DARTS_PER_TURN = 3


@dataclass
class Player:
    name: str
    remaining: int
    history: list[list[Hit]] = field(default_factory=list)


@dataclass
class X01Game:
    player_names: list[str]
    start_score: int = 501
    double_out: bool = True

    players: list[Player] = field(init=False)
    current: int = field(init=False, default=0)
    turn: list[Hit] = field(init=False, default_factory=list)
    winner: Player | None = field(init=False, default=None)

    def __post_init__(self) -> None:
        if not self.player_names:
            raise ValueError("Mindestens ein Spieler nötig")
        self.players = [Player(n, self.start_score) for n in self.player_names]

    @property
    def current_player(self) -> Player:
        return self.players[self.current]

    @property
    def turn_score(self) -> int:
        return sum(h.value for h in self.turn)

    @property
    def remaining_in_turn(self) -> int:
        """Restpunkte des aktuellen Spielers inklusive der Darts dieser Aufnahme."""
        return self.current_player.remaining - self.turn_score

    def throw(self, hit: Hit) -> str:
        """Verbucht einen Dart. Gibt 'ok', 'bust', 'turn_over' oder 'win' zurück."""
        if self.winner:
            raise RuntimeError("Spiel ist bereits beendet")

        self.turn.append(hit)
        rest = self.remaining_in_turn

        if rest < 0 or (self.double_out and rest == 1):
            self._end_turn(bust=True)
            return "bust"
        if rest == 0:
            if self.double_out and not hit.is_double:
                self._end_turn(bust=True)
                return "bust"
            self.winner = self.current_player
            self._end_turn(bust=False)
            return "win"
        if len(self.turn) == DARTS_PER_TURN:
            self._end_turn(bust=False)
            return "turn_over"
        return "ok"

    def undo(self) -> None:
        """Nimmt den letzten Dart der laufenden Aufnahme zurück (Korrekturfunktion)."""
        if self.turn:
            self.turn.pop()

    def next_player(self) -> None:
        """Beendet die Aufnahme vorzeitig, z. B. wenn Darts danebengingen und nicht erkannt wurden."""
        self._end_turn(bust=False)

    def _end_turn(self, bust: bool) -> None:
        player = self.current_player
        player.history.append(list(self.turn))
        if not bust:
            player.remaining -= self.turn_score
        self.turn = []
        self.current = (self.current + 1) % len(self.players)
