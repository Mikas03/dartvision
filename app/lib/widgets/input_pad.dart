import 'package:flutter/material.dart';

import '../models/hit.dart';
import 'button_grid.dart';

/// Tastenfeld zur manuellen Eingabe (und später zur Korrektur erkannter Würfe).
class InputPad extends StatefulWidget {
  const InputPad({super.key, required this.onHit, this.enabled = true});

  final ValueChanged<Hit> onHit;
  final bool enabled;

  @override
  State<InputPad> createState() => _InputPadState();
}

class _InputPadState extends State<InputPad> {
  int _multiplier = 1;

  void _emit(Hit hit) {
    widget.onHit(hit);
    setState(() => _multiplier = 1); // nach jedem Dart zurück auf Single
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('Single')),
            ButtonSegment(value: 2, label: Text('Double')),
            ButtonSegment(value: 3, label: Text('Triple')),
          ],
          selected: {_multiplier},
          showSelectedIcon: false,
          onSelectionChanged: enabled ? (s) => setState(() => _multiplier = s.first) : null,
        ),
        const SizedBox(height: 8),
        ButtonGrid(
          columns: 5,
          children: [
            for (var n = 1; n <= 20; n++)
              _PadButton(label: n.toString(), onPressed: enabled ? () => _emit(Hit(n, _multiplier)) : null),
          ],
        ),
        const SizedBox(height: 6),
        ButtonGrid(
          columns: 3,
          children: [
            _PadButton(
              label: '25',
              // Triple-Bull gibt es nicht, Double + 25 ist das Bull
              onPressed: enabled && _multiplier < 3 ? () => _emit(_multiplier == 2 ? Hit.bull : Hit.outerBull) : null,
            ),
            _PadButton(label: 'Bull', onPressed: enabled ? () => _emit(Hit.bull) : null),
            _PadButton(label: 'Miss', onPressed: enabled ? () => _emit(Hit.miss) : null, subtle: true),
          ],
        ),
      ],
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({required this.label, required this.onPressed, this.subtle = false});

  final String label;
  final VoidCallback? onPressed;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 44),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    return subtle
        ? OutlinedButton(onPressed: onPressed, style: style, child: Text(label))
        : FilledButton.tonal(onPressed: onPressed, style: style, child: Text(label));
  }
}
