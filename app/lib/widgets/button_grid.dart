import 'package:flutter/material.dart';

/// Tasten in einem festen Raster (Zeilen aus gleich breiten Tasten).
///
/// Bewusst ohne GridView: so hat das Raster eine feste Höhe und lässt sich auch in
/// scrollbare Spalten einbetten.
class ButtonGrid extends StatelessWidget {
  const ButtonGrid({
    super.key,
    required this.columns,
    required this.children,
    this.rowHeight = 44,
    this.spacing = 6,
  });

  final int columns;
  final List<Widget> children;
  final double rowHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      final cells = children.sublist(start, (start + columns).clamp(0, children.length));
      rows.add(SizedBox(
        height: rowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < columns; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              Expanded(child: i < cells.length ? cells[i] : const SizedBox()),
            ],
          ],
        ),
      ));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          rows[i],
        ],
      ],
    );
  }
}
