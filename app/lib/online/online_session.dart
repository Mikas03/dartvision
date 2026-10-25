import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/match.dart';
import 'backend.dart';

/// Ein laufendes Online-Match zwischen zwei Accounts.
///
/// Beide Geräte halten das komplette Match. Wer am Zug ist, wirft lokal und schreibt danach den
/// ganzen Spielstand mit einer um 1 höheren Versionsnummer auf den Server; das andere Gerät
/// bekommt die Änderung in Echtzeit und übernimmt sie. Weil immer nur der Spieler am Zug
/// schreibt, gibt es keine Konflikte.
class OnlineSession {
  OnlineSession({
    required Backend this.backend,
    required this.gameId,
    required this.myPlayer,
    required this.version,
  });

  /// Ohne Server – für Tests (Unterklassen überschreiben [push]).
  @visibleForTesting
  OnlineSession.offline({required this.myPlayer})
      : backend = null,
        gameId = '',
        version = 0;

  final Backend? backend;
  final String gameId;

  /// Mein Spieler-Index im Match (Gastgeber 0, Gast 1).
  final int myPlayer;

  /// Zuletzt bekannte Version des Spielstands.
  int version;

  /// Neuer Spielstand vom Gegner.
  void Function(Match match)? onRemoteState;

  /// Das Spiel wurde abgebrochen (Gegner hat es verlassen).
  void Function()? onAborted;

  /// Der eigene Spielstand konnte nicht übertragen werden (z. B. keine Verbindung).
  void Function()? onSyncError;

  Future<void> Function()? _unsubscribe;
  Future<void> _pending = Future.value();

  bool isMine(int player) => player == myPlayer;

  Future<void> start() async {
    final backend = this.backend;
    if (backend == null) return;
    _unsubscribe = await backend.watchGame(gameId, (game) {
      if (game.getStringValue('status') == 'aborted') {
        onAborted?.call();
        return;
      }
      final remoteVersion = game.getIntValue('version');
      if (remoteVersion <= version) return; // eigene Änderung oder veraltet
      version = remoteVersion;
      final state = game.get<Map?>('state');
      if (state != null) onRemoteState?.call(Match.fromJson(Map<String, dynamic>.from(state)));
    });
  }

  /// Schreibt den aktuellen Spielstand. Aufrufe werden der Reihe nach abgearbeitet,
  /// damit Versionen nicht durcheinandergeraten.
  Future<void> push(Match match) {
    final backend = this.backend;
    version++;
    if (backend == null) return Future.value();
    final v = version;
    final body = {
      'state': match.toJson(),
      'version': v,
      'status': match.isOver ? 'finished' : 'playing',
    };
    return _pending = _pending.then((_) async {
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          await backend.updateGame(gameId, body);
          return;
        } catch (_) {
          if (attempt < 3) await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
      onSyncError?.call();
    });
  }

  /// Spiel verlassen; ein noch laufendes Spiel wird als abgebrochen markiert.
  Future<void> leave({required bool finished}) async {
    await _unsubscribe?.call();
    _unsubscribe = null;
    if (!finished && backend != null) {
      try {
        await backend!.updateGame(gameId, {'status': 'aborted'});
      } catch (_) {
        // offline – der Gegner merkt es spätestens beim nächsten Wurf
      }
    }
  }
}
