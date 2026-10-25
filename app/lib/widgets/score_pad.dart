import 'package:flutter/material.dart';

import 'button_grid.dart';

/// Zahlenfeld zur Eingabe der Gesamtpunktzahl einer Aufnahme (z. B. 100).
class ScorePad extends StatefulWidget {
  const ScorePad({super.key, required this.onSubmit, this.enabled = true, this.remaining, this.disabledHint});

  /// Wird mit der eingegebenen Summe aufgerufen. Liefert eine Fehlermeldung oder null, wenn
  /// die Eingabe übernommen wurde.
  final Future<String?> Function(int score) onSubmit;
  final bool enabled;

  /// Restpunkte des Spielers – für die Taste "Rest" (Checkout mit einem Tipp).
  final int? remaining;

  /// Hinweis, warum gerade nichts eingegeben werden kann.
  final String? disabledHint;

  /// Häufige Aufnahmen als Schnelltasten.
  static const quickScores = [26, 41, 45, 60, 81, 85, 100, 121, 140, 180];

  @override
  State<ScorePad> createState() => _ScorePadState();
}

class _ScorePadState extends State<ScorePad> {
  String _input = '';
  String? _error;
  bool _submitting = false;

  void _type(String digit) {
    final next = _input == '0' ? digit : _input + digit;
    if (int.parse(next) > 180) {
      setState(() => _error = 'Mehr als 180 geht nicht');
      return;
    }
    setState(() {
      _input = next;
      _error = null;
    });
  }

  void _backspace() => setState(() {
    _input = _input.isEmpty ? '' : _input.substring(0, _input.length - 1);
    _error = null;
  });

  Future<void> _submit(int score) async {
    if (_submitting) return;
    _submitting = true;
    final error = await widget.onSubmit(score);
    _submitting = false;
    if (!mounted) return;
    setState(() {
      _error = error;
      if (error == null) _input = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.enabled;
    final rest = widget.remaining;
    final message = !enabled ? widget.disabledHint : _error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.only(left: 16),
          decoration: BoxDecoration(
            border: Border.all(color: _error != null ? scheme.error : scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _input.isEmpty ? 'Punkte der Aufnahme' : _input,
                  style: _input.isEmpty
                      ? TextStyle(fontSize: 18, color: scheme.outline)
                      : const TextStyle(fontSize: 30, fontWeight: FontWeight.w500),
                ),
              ),
              IconButton(
                tooltip: 'Löschen',
                onPressed: enabled && _input.isNotEmpty ? _backspace : null,
                icon: const Icon(Icons.backspace_outlined),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 22,
          child: message == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: enabled ? scheme.error : scheme.onSurfaceVariant),
                  ),
                ),
        ),
        ButtonGrid(
          columns: 5,
          rowHeight: 38,
          children: [
            for (final score in ScorePad.quickScores)
              _PadButton(label: '$score', onPressed: enabled ? () => _submit(score) : null, subtle: true),
          ],
        ),
        const SizedBox(height: 8),
        ButtonGrid(
          columns: 3,
          children: [
            for (var d = 1; d <= 9; d++) _PadButton(label: '$d', onPressed: enabled ? () => _type('$d') : null),
            _PadButton(
              label: 'Rest',
              tooltip: 'Checkout: Restpunkte eintragen',
              onPressed: enabled && rest != null && rest <= 170 ? () => _submit(rest) : null,
              subtle: true,
            ),
            _PadButton(label: '0', onPressed: enabled ? () => _type('0') : null),
            _PadButton(
              label: 'OK',
              onPressed: enabled && _input.isNotEmpty ? () => _submit(int.parse(_input)) : null,
              primary: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.label,
    required this.onPressed,
    this.subtle = false,
    this.primary = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool subtle;
  final bool primary;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 40),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    final child = Text(label);
    final button = primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : subtle
        ? OutlinedButton(onPressed: onPressed, style: style, child: child)
        : FilledButton.tonal(onPressed: onPressed, style: style, child: child);
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
