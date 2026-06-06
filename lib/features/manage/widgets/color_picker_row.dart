import 'package:flutter/material.dart';

const kPresetColors = [
  '#DC2626', '#D97706', '#059669', '#0284C7',
  '#7C3AED', '#EC4899', '#F97316', '#84CC16',
  '#06B6D4', '#6366F1', '#475569', '#10B981',
];

class ColorPickerRow extends StatelessWidget {
  const ColorPickerRow({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: kPresetColors.map((hex) {
        final color = _hexToColor(hex);
        final isSelected = hex.toLowerCase() == selected.toLowerCase();
        return GestureDetector(
          onTap: () => onChanged(hex),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.onSurface,
                      width: 2.5,
                    )
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

Color _hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

Color hexToColor(String hex) => _hexToColor(hex);
