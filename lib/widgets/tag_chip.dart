import 'package:flutter/material.dart';
import '../utils/tag_colors.dart';

class TagChip extends StatelessWidget {
  final String label;
  final VoidCallback? onDeleted;
  final VoidCallback? onTap;
  final bool selected;

  const TagChip({
    super.key,
    required this.label,
    this.onDeleted,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = tagColor(label);
    if (onDeleted != null) {
      return Chip(
        label: Text(label, style: TextStyle(color: color)),
        backgroundColor: color.withValues(alpha: 0.12),
        deleteIcon: Icon(Icons.close, size: 14, color: color),
        onDeleted: onDeleted,
      );
    }
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(color: selected ? Colors.white : color),
      ),
      selected: selected,
      selectedColor: color,
      showCheckmark: false,
      onSelected: onTap != null ? (_) => onTap!() : null,
    );
  }
}
