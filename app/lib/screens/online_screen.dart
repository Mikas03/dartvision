import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';

import '../models/match.dart';
import '../models/x01_game.dart';
import '../online/backend.dart';
import '../online/online_session.dart';
import 'game_screen.dart';

/// Online-Bereich: Server verbinden, Account, Online-Spiel erstellen oder beitreten.
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  Backend? _backend;

  @override
  void initState() {
    super.initState();
    Backend.instance().then((b) {
      if (!mounted) return;
      b.addListener(_changed);
      setState(() => _backend = b);
    });
  }

  @override
  void dispose() {
    _backend?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final backend = _backend;
    return Scaffold(
      appBar: AppBar(title: const Text('Online')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: backend == null
                ? const Center(child: CircularProgressIndicator())
                : !backend.configured
                    ? _ServerForm(backend: backend)
                    : !backend.signedIn
                        ? _AuthForm(backend: backend)
                        : _Lobby(backend: backend),
          ),
        ),
      ),
    );
  }
}

/// Fehlermeldung als SnackBar.
void _showError(BuildContext context, Object e) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is BackendException ? e.message : '$e')));

class _ServerForm extends StatefulWidget {
  const _ServerForm({required this.backend});

  final Backend backend;

  @override
  State<_ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends State<_ServerForm> {
  final _url = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Lokal entwickeln: App und Server laufen auf demselben Rechner
    if (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1') _url.text = 'http://127.0.0.1:8090';
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await widget.backend.setServer(_url.text);
    } catch (e) {
      if (mounted) _showError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.dns_outlined, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text('Eigenen Server verbinden', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Accounts, Historie in der Cloud und Online-Spiele laufen über deinen eigenen '
          'PocketBase-Server (z. B. auf einem Raspberry Pi). Die App selbst funktioniert auch ohne.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Server-Adresse',
            hintText: 'https://dart.meine-domain.de',
          ),
          onSubmitted: (_) => _connect(),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _connect, child: Text(_busy ? 'Verbinde …' : 'Verbinden')),
      ],
    );
  }
}

class _AuthForm extends StatefulWidget {
  const _AuthForm({required this.backend});

  final Backend backend;

  @override
  State<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<_AuthForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_register && _name.text.trim().isEmpty) {
      _showError(context, const BackendException('Bitte einen Namen eingeben.'));
      return;
    }
    if (_password.text.length < 8) {
      _showError(context, const BackendException('Das Passwort braucht mindestens 8 Zeichen.'));
      return;
    }
    setState(() => _busy = true);
    try {
      if (_register) {
        await widget.backend.register(_name.text, _email.text, _password.text);
      } else {
        await widget.backend.signIn(_email.text, _password.text);
      }
    } catch (e) {
      if (mounted) _showError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AutofillGroup(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Anmelden')),
              ButtonSegment(value: true, label: Text('Registrieren')),
            ],
            selected: {_register},
            onSelectionChanged: (s) => setState(() => _register = s.first),
          ),
          const SizedBox(height: 20),
          if (_register) ...[
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.nickname],
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Spielername'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'E-Mail'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Passwort (mind. 8 Zeichen)'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Bitte warten …' : (_register ? 'Account erstellen' : 'Anmelden')),
          ),
          const SizedBox(height: 24),
          Text('Server: ${widget.backend.serverUrl}',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          TextButton(onPressed: widget.backend.forgetServer, child: const Text('Anderen Server wählen')),
        ],
      ),
    );
  }
}

class _Lobby extends StatefulWidget {
  const _Lobby({required this.backend});

  final Backend backend;

  @override
  State<_Lobby> createState() => _LobbyState();
}

class _LobbyState extends State<_Lobby> {
  final _code = TextEditingController();
  MatchSettings _settings = const MatchSettings();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final game = await widget.backend.createGame(_settings);
      if (mounted) await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WaitingRoom(game: game, host: true)));
    } catch (e) {
      if (mounted) _showError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _join() async {
    if (_code.text.trim().length < 5) return;
    setState(() => _busy = true);
    try {
      final game = await widget.backend.joinGame(_code.text);
      if (mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WaitingRoom(game: game, host: false)));
      }
    } catch (e) {
      if (mounted) _showError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _sync() async {
    try {
      final added = await widget.backend.syncHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(added == 0 ? 'Historie ist aktuell' : '$added Matches vom Server geholt')),
        );
      }
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = widget.backend;
    final s = _settings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(child: Text(b.userName.isEmpty ? '?' : b.userName[0].toUpperCase())),
            title: Text(b.userName),
            subtitle: Text(b.serverUrl ?? ''),
            trailing: PopupMenuButton<String>(
              onSelected: (v) => v == 'sync' ? _sync() : b.signOut(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'sync', child: Text('Historie abgleichen')),
                PopupMenuItem(value: 'logout', child: Text('Abmelden')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Online-Spiel erstellen', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final m in GameMode.values.where((m) => !m.isTraining))
              ChoiceChip(
                label: Text(m.title),
                selected: s.mode == m,
                onSelected: (_) => setState(() => _settings = s.copyWith(mode: m)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (s.mode == GameMode.x01)
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 301, label: Text('301')),
              ButtonSegment(value: 501, label: Text('501')),
              ButtonSegment(value: 701, label: Text('701')),
            ],
            selected: {s.startScore},
            onSelectionChanged: (v) => setState(() => _settings = s.copyWith(startScore: v.first, outRule: OutRule.double)),
          ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1 Leg')),
            ButtonSegment(value: 3, label: Text('Bo3')),
            ButtonSegment(value: 5, label: Text('Bo5')),
          ],
          selected: {s.bestOf},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _settings = s.copyWith(bestOf: v.first)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.add),
          label: const Text('Spiel erstellen'),
        ),
        const Divider(height: 40),
        Text('Spiel beitreten', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                maxLength: 5,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]'))],
                decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Code', counterText: ''),
                onSubmitted: (_) => _join(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(onPressed: _busy ? null : _join, child: const Text('Beitreten')),
          ],
        ),
      ],
    );
  }
}

/// Warteraum: Gastgeber zeigt den Code und wartet auf den Gast; der Gast wartet auf den Start.
class WaitingRoom extends StatefulWidget {
  const WaitingRoom({super.key, required this.game, required this.host});

  final RecordModel game;
  final bool host;

  @override
  State<WaitingRoom> createState() => _WaitingRoomState();
}

class _WaitingRoomState extends State<WaitingRoom> {
  late RecordModel _game = widget.game;
  Future<void> Function()? _unsubscribe;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  Future<void> _watch() async {
    final backend = await Backend.instance();
    _unsubscribe = await backend.watchGame(_game.id, _onChange);
    // Falls der Gegner schon vor dem Verbinden beigetreten ist
    try {
      await _onChange(await backend.client!.collection('games').getOne(_game.id));
    } catch (_) {}
  }

  Future<void> _onChange(RecordModel game) async {
    if (!mounted || _started) return;
    setState(() => _game = game);
    final backend = await Backend.instance();
    final status = game.getStringValue('status');
    if (status == 'aborted') {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (widget.host && status == 'waiting' && game.getStringValue('guest').isNotEmpty) {
      // Gast ist da: Gastgeber baut das Match und schreibt den ersten Spielstand
      final match = Match(
        settings: MatchSettings.fromJson(Map<String, dynamic>.from(game.get<Map>('settings'))),
        players: [
          backend.me!,
          MatchPlayer(
            name: game.getStringValue('guestName'),
            profileId: '${Backend.accountProfilePrefix}${game.getStringValue('guest')}',
          ),
        ],
        id: 'online-${game.id}',
      );
      await backend.updateGame(game.id, {'state': match.toJson(), 'version': 1, 'status': 'playing'});
      _open(match, 1);
    } else if (!widget.host && status == 'playing' && game.get<Map?>('state') != null) {
      _open(Match.fromJson(Map<String, dynamic>.from(game.get<Map>('state'))), game.getIntValue('version'));
    }
  }

  Future<void> _open(Match match, int version) async {
    if (_started || !mounted) return;
    _started = true;
    await _unsubscribe?.call();
    final backend = await Backend.instance();
    final session = OnlineSession(backend: backend, gameId: _game.id, myPlayer: widget.host ? 0 : 1, version: version);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GameScreen(match: match, online: session),
    ));
  }

  Future<void> _cancel() async {
    await _unsubscribe?.call();
    final backend = await Backend.instance();
    try {
      if (widget.host) {
        await backend.updateGame(_game.id, {'status': 'aborted'});
      } else {
        await backend.updateGame(_game.id, {'guest': null, 'guestName': ''});
      }
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _game.getStringValue('code');
    final settings = MatchSettings.fromJson(Map<String, dynamic>.from(_game.get<Map>('settings')));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.host ? 'Warte auf Gegner' : 'Warte auf Start')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  settings.mode == GameMode.x01 ? '${settings.startScore}' : settings.mode.title,
                  style: theme.textTheme.titleLarge,
                ),
                if (settings.bestOf > 1) Text('Best of ${settings.bestOf}'),
                const SizedBox(height: 24),
                if (widget.host) ...[
                  const Text('Schick deinem Gegner diesen Code:'),
                  const SizedBox(height: 8),
                  SelectableText(code,
                      style: theme.textTheme.displayMedium?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code kopiert')));
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Kopieren'),
                  ),
                ] else
                  Text('Gegen ${_game.getStringValue('hostName')}', style: theme.textTheme.titleMedium),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                OutlinedButton(onPressed: _cancel, child: const Text('Abbrechen')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
