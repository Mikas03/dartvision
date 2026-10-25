import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/match.dart';

/// Ein Spielerprofil auf dem Gerät. Später lässt es sich mit einem Account verknüpfen.
class PlayerProfile {
  const PlayerProfile({required this.id, required this.name, required this.createdAt});

  final String id;
  final String name;
  final DateTime createdAt;

  PlayerProfile copyWith({String? name}) => PlayerProfile(id: id, name: name ?? this.name, createdAt: createdAt);

  Map<String, Object> toJson() => {'id': id, 'name': name, 'created': createdAt.toIso8601String()};

  factory PlayerProfile.fromJson(Map<String, dynamic> json) => PlayerProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['created'] as String),
      );
}

/// Zusammenfassung eines gespeicherten Matches (für die Liste) plus der komplette Verlauf.
class MatchRecord {
  MatchRecord({
    required this.id,
    required this.finishedAt,
    required this.mode,
    required this.description,
    required this.players,
    required this.legWins,
    required this.winner,
    required this.stats,
    required this.matchJson,
  });

  factory MatchRecord.fromMatch(Match match, {DateTime? finishedAt}) => MatchRecord(
        id: match.id,
        finishedAt: finishedAt ?? DateTime.now(),
        mode: match.settings.mode,
        description: match.description,
        players: match.players,
        legWins: match.legWins,
        winner: match.winner,
        stats: match.stats(),
        matchJson: match.toJson(),
      );

  final String id;
  final DateTime finishedAt;
  final GameMode mode;
  final String description;
  final List<MatchPlayer> players;
  final List<int> legWins;
  final int? winner;
  final List<Map<String, num>> stats;

  /// Vollständiges Match (jeder Wurf) – lässt sich mit [Match.fromJson] wiederherstellen.
  final Map<String, dynamic> matchJson;

  Match restore() => Match.fromJson(matchJson);

  Map<String, Object?> toJson() => {
        'id': id,
        'finished': finishedAt.toIso8601String(),
        'mode': mode.name,
        'description': description,
        'players': [for (final p in players) p.toJson()],
        'legWins': legWins,
        'winner': winner,
        'stats': stats,
        'match': matchJson,
      };

  factory MatchRecord.fromJson(Map<String, dynamic> json) => MatchRecord(
        id: json['id'] as String,
        finishedAt: DateTime.parse(json['finished'] as String),
        mode: GameMode.values.byName(json['mode'] as String),
        description: json['description'] as String,
        players: [for (final p in (json['players'] as List).cast<Map<String, dynamic>>()) MatchPlayer.fromJson(p)],
        legWins: (json['legWins'] as List).cast<int>(),
        winner: json['winner'] as int?,
        stats: [for (final s in json['stats'] as List) (s as Map).cast<String, num>()],
        matchJson: json['match'] as Map<String, dynamic>,
      );
}

/// Lokale Datenhaltung (im Browser: localStorage). Bewusst hinter einer kleinen Klasse,
/// damit sie später gegen einen Cloud-Speicher (Accounts) getauscht werden kann.
class LocalStore {
  LocalStore._(this._prefs);

  static LocalStore? _instance;

  static Future<LocalStore> instance() async => _instance ??= LocalStore._(await SharedPreferences.getInstance());

  /// Nur für Tests.
  static void resetForTests() => _instance = null;

  final SharedPreferences _prefs;

  static const _profilesKey = 'profiles';
  static const _historyKey = 'match_history';
  static const _speechKey = 'speech_enabled';

  /// Ältere Matches werden gelöscht, damit der Speicher nicht vollläuft.
  static const maxHistory = 300;

  // ---------------------------------------------------------------- Profile

  List<PlayerProfile> get profiles {
    final raw = _prefs.getString(_profilesKey);
    if (raw == null) return [];
    return [for (final p in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) PlayerProfile.fromJson(p)];
  }

  Future<void> _saveProfiles(List<PlayerProfile> profiles) =>
      _prefs.setString(_profilesKey, jsonEncode([for (final p in profiles) p.toJson()]));

  Future<PlayerProfile> addProfile(String name) async {
    final profile = PlayerProfile(
      id: '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(1 << 16)}',
      name: name.trim(),
      createdAt: DateTime.now(),
    );
    await _saveProfiles([...profiles, profile]);
    return profile;
  }

  /// Legt ein Profil mit fester ID an (z. B. für den Account) oder aktualisiert dessen Namen.
  Future<void> ensureProfile(String id, String name) async {
    final list = profiles;
    final index = list.indexWhere((p) => p.id == id);
    if (index >= 0) {
      if (list[index].name != name) list[index] = list[index].copyWith(name: name);
    } else {
      list.insert(0, PlayerProfile(id: id, name: name, createdAt: DateTime.now()));
    }
    await _saveProfiles(list);
  }

  Future<void> renameProfile(String id, String name) =>
      _saveProfiles([for (final p in profiles) p.id == id ? p.copyWith(name: name.trim()) : p]);

  /// Löscht das Profil; gespeicherte Matches bleiben (mit dem Namen von damals).
  Future<void> deleteProfile(String id) => _saveProfiles([for (final p in profiles) if (p.id != id) p]);

  // ---------------------------------------------------------------- Historie

  /// Alle gespeicherten Matches, neueste zuerst.
  List<MatchRecord> get history {
    final raw = _prefs.getString(_historyKey);
    if (raw == null) return [];
    final records = <MatchRecord>[];
    for (final r in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) {
      try {
        records.add(MatchRecord.fromJson(r));
      } catch (_) {
        // Einzelne kaputte Einträge überspringen statt die ganze Historie zu verlieren
      }
    }
    return records;
  }

  Future<void> saveMatch(Match match, {DateTime? finishedAt}) async {
    final records = [MatchRecord.fromMatch(match, finishedAt: finishedAt), ...history.where((r) => r.id != match.id)]
      ..sort((a, b) => b.finishedAt.compareTo(a.finishedAt));
    await _prefs.setString(_historyKey, jsonEncode([for (final r in records.take(maxHistory)) r.toJson()]));
  }

  Future<void> deleteMatch(String id) async {
    final records = history.where((r) => r.id != id);
    await _prefs.setString(_historyKey, jsonEncode([for (final r in records) r.toJson()]));
  }

  // ---------------------------------------------------------------- Einstellungen

  bool get speechEnabled => _prefs.getBool(_speechKey) ?? false;
  Future<void> setSpeechEnabled(bool on) => _prefs.setBool(_speechKey, on);

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
}

/// Statistik eines Spielers über alle gespeicherten Matches.
class ProfileStats {
  ProfileStats(this.profileId, List<MatchRecord> history) {
    for (final r in history.reversed) {
      final p = r.players.indexWhere((pl) => pl.profileId == profileId);
      if (p < 0) continue;
      matches++;
      if (r.winner == p) wins++;
      final s = r.stats[p];
      if (r.mode == GameMode.x01) {
        final avg = s['average'];
        if (avg != null) x01Averages.add(avg.toDouble());
        highestCheckout = [highestCheckout, (s['highestCheckout'] ?? 0).toInt()].reduce((a, b) => a > b ? a : b);
        count180 += (s['180'] ?? 0).toInt();
        count140 += (s['140+'] ?? 0).toInt();
        count100 += (s['100+'] ?? 0).toInt();
      }
      if (r.mode == GameMode.cricket && s['mpr'] != null) cricketMpr.add(s['mpr']!.toDouble());
    }
  }

  final String profileId;
  int matches = 0;
  int wins = 0;

  /// X01-Averages der Matches in zeitlicher Reihenfolge (ältestes zuerst).
  final List<double> x01Averages = [];
  final List<double> cricketMpr = [];
  int highestCheckout = 0;
  int count180 = 0;
  int count140 = 0;
  int count100 = 0;

  double? get averageX01 => x01Averages.isEmpty ? null : x01Averages.reduce((a, b) => a + b) / x01Averages.length;
  double? get averageMpr => cricketMpr.isEmpty ? null : cricketMpr.reduce((a, b) => a + b) / cricketMpr.length;
}
