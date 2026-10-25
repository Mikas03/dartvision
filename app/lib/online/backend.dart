import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../data/storage.dart';
import '../models/match.dart';

/// Verbindung zum eigenen PocketBase-Server (z. B. auf dem Raspberry Pi):
/// Accounts, Historie in der Cloud und Online-Spiele.
class Backend extends ChangeNotifier {
  Backend._(this._store);

  static Backend? _instance;

  static Future<Backend> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final backend = Backend._(await LocalStore.instance());
    final url = backend._store.getString(_serverKey);
    if (url != null && url.isNotEmpty) backend._connect(url);
    return _instance = backend;
  }

  /// Nur für Tests.
  static void resetForTests() => _instance = null;

  static const _serverKey = 'server_url';
  static const _authKey = 'pb_auth';

  /// Profile, die zu einem Account gehören, haben diese ID-Vorsilbe (gefolgt von der Account-ID).
  static const accountProfilePrefix = 'acc:';

  final LocalStore _store;
  PocketBase? _pb;

  PocketBase? get client => _pb;
  String? get serverUrl => _pb?.baseURL;
  bool get configured => _pb != null;
  bool get signedIn => _pb?.authStore.isValid ?? false;
  String? get userId => signedIn ? _pb!.authStore.record?.id : null;

  String get userName {
    final record = _pb?.authStore.record;
    if (record == null) return '';
    final name = record.getStringValue('name');
    return name.isNotEmpty ? name : record.getStringValue('email').split('@').first;
  }

  /// Lokale Profil-ID des angemeldeten Accounts.
  String? get accountProfileId => userId == null ? null : '$accountProfilePrefix$userId';

  /// Wer als "ich" mitspielt – für Online-Spiele und die Historie.
  MatchPlayer? get me =>
      userId == null ? null : MatchPlayer(name: userName, profileId: accountProfileId);

  void _connect(String url) {
    _pb = PocketBase(
      url,
      authStore: AsyncAuthStore(
        save: (data) => _store.setString(_authKey, data),
        initial: _store.getString(_authKey),
      ),
    );
    _pb!.authStore.onChange.listen((_) => notifyListeners());
  }

  /// Prüft die Adresse (Server erreichbar?) und speichert sie.
  Future<void> setServer(String url) async {
    var clean = url.trim();
    if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) clean = 'https://$clean';
    final test = PocketBase(clean);
    try {
      await test.health.check();
    } catch (e) {
      throw BackendException('Server unter $clean nicht erreichbar.');
    }
    await _store.setString(_serverKey, clean);
    await _store.setString(_authKey, '');
    _connect(clean);
    notifyListeners();
  }

  Future<void> forgetServer() async {
    _pb?.authStore.clear();
    _pb = null;
    await _store.setString(_serverKey, '');
    notifyListeners();
  }

  // ---------------------------------------------------------------- Accounts

  Future<void> signIn(String email, String password) async {
    final pb = _require();
    try {
      await pb.collection('users').authWithPassword(email.trim(), password);
    } on ClientException catch (e) {
      throw BackendException(e.statusCode == 400 ? 'E-Mail oder Passwort falsch.' : _message(e));
    }
    await _afterSignIn();
  }

  Future<void> register(String name, String email, String password) async {
    final pb = _require();
    try {
      await pb.collection('users').create(body: {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'passwordConfirm': password,
      });
    } on ClientException catch (e) {
      throw BackendException(_message(e));
    }
    await signIn(email, password);
  }

  void signOut() {
    _pb?.authStore.clear();
    notifyListeners();
  }

  /// Nach dem Anmelden: lokales Profil für den Account anlegen und Historie abgleichen.
  Future<void> _afterSignIn() async {
    final id = accountProfileId;
    if (id != null) await _store.ensureProfile(id, userName);
    unawaited(syncHistory().catchError((_) => 0));
    notifyListeners();
  }

  // ---------------------------------------------------------------- Historie

  /// Account-IDs der Spieler, die zu einem Account gehören.
  static List<String> participantsOf(Match match) => [
        for (final p in match.players)
          if (p.profileId?.startsWith(accountProfilePrefix) ?? false) p.profileId!.substring(accountProfilePrefix.length),
      ];

  /// Lädt ein beendetes Match hoch, wenn der angemeldete Account mitgespielt hat.
  Future<void> uploadMatch(Match match) async {
    final me = userId;
    if (me == null) return;
    final participants = participantsOf(match);
    if (!participants.contains(me)) return;
    try {
      await _pb!.collection('matches').create(body: {
        'owner': me,
        'participants': participants,
        'matchId': match.id,
        'mode': match.settings.mode.name,
        'description': match.description,
        'finished': DateTime.now().toUtc().toIso8601String(),
        'data': match.toJson(),
      });
    } on ClientException catch (e) {
      if (e.statusCode != 400) rethrow; // 400: schon vorhanden (z. B. vom Gegner hochgeladen)
    }
  }

  /// Holt alle Matches des Accounts vom Server, die lokal noch fehlen. Liefert die Anzahl neuer Matches.
  Future<int> syncHistory() async {
    if (!signedIn) return 0;
    final records = await _pb!.collection('matches').getFullList(sort: '-finished');
    final known = {for (final r in _store.history) r.id};
    var added = 0;
    for (final r in records) {
      if (known.contains(r.getStringValue('matchId'))) continue;
      try {
        final match = Match.fromJson(Map<String, dynamic>.from(r.get<Map>('data')));
        final finished = DateTime.tryParse(r.getStringValue('finished'))?.toLocal();
        await _store.saveMatch(match, finishedAt: finished);
        added++;
      } catch (_) {
        // unlesbarer Eintrag (z. B. neuere App-Version) – überspringen
      }
    }
    if (added > 0) notifyListeners();
    return added;
  }

  // ---------------------------------------------------------------- Online-Spiele

  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // ohne 0/O und 1/I

  /// Legt ein Online-Spiel an und liefert es (mit Beitritts-Code).
  Future<RecordModel> createGame(MatchSettings settings) async {
    final pb = _require();
    final random = math.Random.secure();
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = List.generate(5, (_) => _codeChars[random.nextInt(_codeChars.length)]).join();
      try {
        return await pb.collection('games').create(body: {
          'code': code,
          'host': userId,
          'hostName': userName,
          'status': 'waiting',
          'settings': settings.toJson(),
          'version': 0,
        });
      } on ClientException catch (e) {
        if (e.statusCode != 400) throw BackendException(_message(e)); // 400: Code schon vergeben -> neu würfeln
      }
    }
    throw const BackendException('Konnte kein Spiel anlegen.');
  }

  /// Tritt einem wartenden Spiel per Code bei.
  Future<RecordModel> joinGame(String code) async {
    final pb = _require();
    final clean = code.trim().toUpperCase();
    final found = await pb
        .collection('games')
        .getList(filter: pb.filter('code = {:code} && status = "waiting"', {'code': clean}), perPage: 1);
    if (found.items.isEmpty) throw BackendException('Kein offenes Spiel mit Code $clean gefunden.');
    final game = found.items.first;
    if (game.getStringValue('host') == userId) throw const BackendException('Das ist dein eigenes Spiel.');
    try {
      return await pb.collection('games').update(game.id, body: {'guest': userId, 'guestName': userName});
    } on ClientException catch (_) {
      throw const BackendException('Jemand anderes war schneller.');
    }
  }

  Future<RecordModel> updateGame(String id, Map<String, dynamic> body) => _require().collection('games').update(id, body: body);

  /// Beobachtet ein Spiel; [onChange] wird bei jeder Änderung aufgerufen.
  Future<Future<void> Function()> watchGame(String id, void Function(RecordModel game) onChange) async {
    final pb = _require();
    final unsubscribe = await pb.collection('games').subscribe(id, (e) {
      final record = e.record;
      if (record != null) onChange(record);
    });
    return unsubscribe;
  }

  PocketBase _require() {
    final pb = _pb;
    if (pb == null) throw const BackendException('Kein Server eingerichtet.');
    return pb;
  }

  static String _message(ClientException e) {
    if (e.statusCode == 0) return 'Server nicht erreichbar.';
    final data = e.response['data'];
    if (data is Map && data.isNotEmpty) {
      final first = data.values.first;
      if (first is Map && first['message'] is String) return first['message'] as String;
    }
    return (e.response['message'] as String?) ?? 'Fehler ${e.statusCode}';
  }
}

class BackendException implements Exception {
  const BackendException(this.message);
  final String message;

  @override
  String toString() => message;
}
