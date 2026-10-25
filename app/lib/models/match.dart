import 'dart:math' as math;

import 'bot.dart';
import 'cricket_game.dart';
import 'dart_game.dart';
import 'practice_games.dart';
import 'x01_game.dart';

/// Alle Spielmodi.
enum GameMode {
  x01('X01', '301, 501, 701 – auf genau 0 spielen'),
  cricket('Cricket', '15–20 und Bull schließen, Punkte sammeln'),
  aroundTheClock('Around the Clock', '1 bis 20 der Reihe nach, dann Bull'),
  shanghai('Shanghai', '7 Runden, Single + Double + Triple gewinnt sofort'),
  bobs27("Bob's 27", 'Doppel-Training: D1 bis D20 und Bull'),
  checkoutTraining('Checkout-Training', 'Zufällige Reste in 3 Darts auschecken');

  const GameMode(this.title, this.description);

  final String title;
  final String description;

  bool get isTraining => this == bobs27 || this == checkoutTraining;

  /// Nur bei X01 kann man die Summe einer Aufnahme eingeben.
  bool get supportsTotalInput => this == x01;
}

/// Ein Teilnehmer eines Matches: Mensch (optional mit Profil) oder Dartbot.
class MatchPlayer {
  const MatchPlayer({required this.name, this.profileId, this.botLevel});

  factory MatchPlayer.bot(int level) => MatchPlayer(name: 'Bot $level', botLevel: level);

  final String name;

  /// Verknüpfung zum Spielerprofil (für Statistiken über mehrere Matches).
  final String? profileId;

  /// Stufe 1–10, wenn es ein Dartbot ist.
  final int? botLevel;

  bool get isBot => botLevel != null;

  Map<String, Object> toJson() => {'name': name, 'profile': ?profileId, 'bot': ?botLevel};

  factory MatchPlayer.fromJson(Map<String, dynamic> json) =>
      MatchPlayer(name: json['name'] as String, profileId: json['profile'] as String?, botLevel: json['bot'] as int?);
}

/// Einstellungen eines Matches.
class MatchSettings {
  const MatchSettings({
    this.mode = GameMode.x01,
    this.startScore = 501,
    this.doubleIn = false,
    this.outRule = OutRule.double,
    this.cutThroat = false,
    this.multiplesCount = false,
    this.bestOf = 1,
    this.trainingRounds = 10,
  });

  final GameMode mode;
  final int startScore;
  final bool doubleIn;
  final OutRule outRule;
  final bool cutThroat;
  final bool multiplesCount;

  /// Best of N Legs (1, 3, 5, 7 …).
  final int bestOf;

  /// Runden beim Checkout-Training.
  final int trainingRounds;

  int get legsToWin => bestOf ~/ 2 + 1;

  MatchSettings copyWith({
    GameMode? mode,
    int? startScore,
    bool? doubleIn,
    OutRule? outRule,
    bool? cutThroat,
    bool? multiplesCount,
    int? bestOf,
    int? trainingRounds,
  }) =>
      MatchSettings(
        mode: mode ?? this.mode,
        startScore: startScore ?? this.startScore,
        doubleIn: doubleIn ?? this.doubleIn,
        outRule: outRule ?? this.outRule,
        cutThroat: cutThroat ?? this.cutThroat,
        multiplesCount: multiplesCount ?? this.multiplesCount,
        bestOf: bestOf ?? this.bestOf,
        trainingRounds: trainingRounds ?? this.trainingRounds,
      );

  Map<String, Object> toJson() => {
        'mode': mode.name,
        'start': startScore,
        'doubleIn': doubleIn,
        'out': outRule.name,
        'cutThroat': cutThroat,
        'multiples': multiplesCount,
        'bestOf': bestOf,
        'rounds': trainingRounds,
      };

  factory MatchSettings.fromJson(Map<String, dynamic> json) => MatchSettings(
        mode: GameMode.values.byName(json['mode'] as String),
        startScore: json['start'] as int? ?? 501,
        doubleIn: json['doubleIn'] as bool? ?? false,
        outRule: OutRule.values.asNameMap()[json['out']] ?? OutRule.double,
        cutThroat: json['cutThroat'] as bool? ?? false,
        multiplesCount: json['multiples'] as bool? ?? false,
        bestOf: json['bestOf'] as int? ?? 1,
        trainingRounds: json['rounds'] as int? ?? 10,
      );
}

/// Ein Match aus einem oder mehreren Legs. Der Anwurf wechselt von Leg zu Leg.
///
/// Das Match lässt sich vollständig als JSON speichern (Einstellungen, Spieler und jeder Wurf)
/// und daraus wiederherstellen – Grundlage für Historie und später fürs Online-Spiel.
class Match {
  Match({required this.settings, required List<MatchPlayer> players, String? id, DateTime? startedAt})
      : players = List.unmodifiable(players),
        id = id ?? _newId(),
        startedAt = startedAt ?? DateTime.now() {
    if (players.isEmpty) throw ArgumentError('Mindestens ein Spieler nötig');
    _legs.add(_createLeg(0));
  }

  final MatchSettings settings;
  final List<MatchPlayer> players;
  final String id;
  final DateTime startedAt;

  final List<DartGame> _legs = [];
  final List<int> _seeds = [];

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(1 << 20).toRadixString(36)}';

  List<DartGame> get legs => List.unmodifiable(_legs);

  /// Das laufende Leg.
  DartGame get leg => _legs.last;

  List<String> get names => [for (final p in players) p.name];

  DartGame _createLeg(int starter, {int? seed}) {
    final s = settings;
    final names = this.names;
    final legSeed = seed ?? math.Random().nextInt(1 << 30);
    _seeds.add(legSeed);
    return switch (s.mode) {
      GameMode.x01 => X01Game(
          players: names,
          startingPlayer: starter,
          startScore: s.startScore,
          doubleIn: s.doubleIn,
          doubleOut: s.outRule != OutRule.straight,
          masterOut: s.outRule == OutRule.master,
        ),
      GameMode.cricket => CricketGame(players: names, startingPlayer: starter, cutThroat: s.cutThroat),
      GameMode.aroundTheClock =>
        AroundTheClockGame(players: names, startingPlayer: starter, multiplesCount: s.multiplesCount),
      GameMode.shanghai => ShanghaiGame(players: names, startingPlayer: starter),
      GameMode.bobs27 => Bobs27Game(players: names, startingPlayer: starter),
      GameMode.checkoutTraining =>
        CheckoutTrainingGame(players: names, startingPlayer: starter, rounds: s.trainingRounds, seed: legSeed),
    };
  }

  /// Gewonnene Legs je Spieler.
  List<int> get legWins {
    final wins = List.filled(players.length, 0);
    for (final l in _legs) {
      if (l.winner != null) wins[l.winner!]++;
    }
    return wins;
  }

  /// Sieger des Matches, sobald jemand genug Legs gewonnen hat.
  int? get winner {
    final wins = legWins;
    for (var p = 0; p < wins.length; p++) {
      if (wins[p] >= settings.legsToWin) return p;
    }
    return null;
  }

  bool get isOver => winner != null;

  /// Ob das laufende Leg vorbei ist, das Match aber noch nicht.
  bool get legOver => leg.isOver && !isOver;

  void startNextLeg() {
    if (!leg.isOver || isOver) throw StateError('Das laufende Leg ist noch nicht vorbei');
    _legs.add(_createLeg(_legs.length % players.length));
  }

  bool get canUndo => leg.canUndo || _legs.length > 1;

  /// Rückgängig; am Anfang eines Legs geht es zurück ins vorige Leg (dessen letzter Dart).
  void undo() {
    if (!leg.canUndo && _legs.length > 1) {
      _legs.removeLast();
      _seeds.removeLast();
    }
    leg.undo();
  }

  // ---------------------------------------------------------------- Speichern

  Map<String, Object> toJson() => {
        'id': id,
        'started': startedAt.toIso8601String(),
        'settings': settings.toJson(),
        'players': [for (final p in players) p.toJson()],
        'legs': [
          for (var i = 0; i < _legs.length; i++)
            {
              'starter': _legs[i].startingPlayer,
              'seed': _seeds[i],
              'turns': _legs[i].turnsToJson(),
            },
        ],
      };

  /// Stellt ein gespeichertes Match wieder her, indem alle Würfe nachgespielt werden.
  factory Match.fromJson(Map<String, dynamic> json) {
    final legsJson = (json['legs'] as List).cast<Map<String, dynamic>>();
    final match = Match._restore(
      settings: MatchSettings.fromJson(json['settings'] as Map<String, dynamic>),
      players: [for (final p in (json['players'] as List).cast<Map<String, dynamic>>()) MatchPlayer.fromJson(p)],
      id: json['id'] as String,
      startedAt: DateTime.parse(json['started'] as String),
    );
    for (final legJson in legsJson) {
      final leg = match._createLeg(legJson['starter'] as int, seed: legJson['seed'] as int?);
      match._legs.add(leg);
      leg.replay(legJson['turns'] as List);
    }
    return match;
  }

  Match._restore({required this.settings, required List<MatchPlayer> players, required this.id, required this.startedAt})
      : players = List.unmodifiable(players);

  // ---------------------------------------------------------------- Statistik

  /// Kennzahlen je Spieler über alle Legs (Schlüssel siehe [statLabels]).
  List<Map<String, num>> stats() => [for (var p = 0; p < players.length; p++) _statsFor(p)];

  Map<String, num> _statsFor(int p) {
    final darts = _legs.fold(0, (sum, l) => sum + l.turnsOf(p).fold(0, (s, t) => s + t.dartCount));
    final result = <String, num>{'legs': legWins[p], 'darts': darts};
    switch (settings.mode) {
      case GameMode.x01:
        final legs = _legs.cast<X01Game>();
        final points = legs.fold(0, (sum, l) => sum + l.turnsOf(p).fold(0, (s, t) => s + l.turnPoints(t)));
        final checkouts = [for (final l in legs) ?l.checkout(p)];
        final f9 = [for (final l in legs) if (l.roundsPlayed(p) >= 3) l.first9Average(p)];
        result.addAll({
          if (darts > 0) 'average': points / darts * dartsPerTurn,
          if (f9.isNotEmpty) 'first9': f9.reduce((a, b) => a + b) / f9.length,
          if (checkouts.isNotEmpty) 'highestCheckout': checkouts.reduce(math.max),
          '100+': legs.fold(0, (s, l) => s + l.countAtLeast(p, 100) - l.countAtLeast(p, 140)),
          '140+': legs.fold(0, (s, l) => s + l.countAtLeast(p, 140) - l.countAtLeast(p, 180)),
          '180': legs.fold(0, (s, l) => s + l.countAtLeast(p, 180)),
        });
      case GameMode.cricket:
        final legs = _legs.cast<CricketGame>();
        final marks = legs.fold(0, (sum, l) => sum + l.turnsOf(p).fold(0, (s, t) => s + l.turnMarks(t)));
        if (darts > 0) result['mpr'] = marks / darts * dartsPerTurn;
      case GameMode.aroundTheClock:
        break; // Darts reichen als Kennzahl
      case GameMode.shanghai:
        result['score'] = (leg as ShanghaiGame).score(p);
      case GameMode.bobs27:
        result['score'] = (leg as Bobs27Game).score(p);
      case GameMode.checkoutTraining:
        final legs = _legs.cast<CheckoutTrainingGame>();
        final ok = legs.fold(0, (s, l) => s + l.successes(p));
        final tries = legs.fold(0, (s, l) => s + l.roundsPlayed(p));
        result['checkouts'] = ok;
        if (tries > 0) result['checkoutRate'] = ok / tries * 100;
    }
    return result;
  }

  /// Anzeigenamen der Kennzahlen.
  static const statLabels = {
    'legs': 'Legs',
    'darts': 'Darts',
    'average': 'Average',
    'first9': 'First 9',
    'highestCheckout': 'Höchster Checkout',
    '100+': '100+',
    '140+': '140+',
    '180': '180',
    'mpr': 'Marks pro Runde',
    'score': 'Punkte',
    'checkouts': 'Checkouts',
    'checkoutRate': 'Checkout-Quote %',
  };

  /// Beschreibung der Einstellungen, z. B. "501 · Double Out · Best of 3".
  String get description {
    final l = leg;
    return [
      settings.mode == GameMode.x01 ? l.title : settings.mode.title,
      ?l.subtitle,
      if (settings.bestOf > 1) 'Best of ${settings.bestOf}',
    ].join(' · ');
  }

  /// Bot-Instanzen für die Bot-Spieler (Index → Bot).
  Map<int, DartBot> createBots({math.Random? random}) => {
        for (var p = 0; p < players.length; p++)
          if (players[p].isBot) p: DartBot(players[p].botLevel!, random: random),
      };
}
