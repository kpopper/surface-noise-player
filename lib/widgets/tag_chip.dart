import 'package:flutter/material.dart';

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
    if (onDeleted != null) {
      return Chip(
        label: Text(label),
        deleteIcon: const Icon(Icons.close, size: 14),
        onDeleted: onDeleted,
      );
    }
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onTap != null ? (_) => onTap!() : null,
    );
  }
}
