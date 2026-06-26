import 'package:flutter/material.dart';

const List<Color> _palette = [
  Color(0xFF26A69A), // teal
  Color(0xFF7E57C2), // deep purple
  Color(0xFF1E88E5), // blue
  Color(0xFF43A047), // green
  Color(0xFFEC407A), // pink
  Color(0xFF00ACC1), // cyan
  Color(0xFFFF7043), // deep orange
  Color(0xFF5C6BC0), // indigo
];

Color tagColor(String tag) => _palette[tag.hashCode.abs() % _palette.length];
