import 'dart:io';
import 'package:flutter/material.dart';

class ArtThumbnail extends StatelessWidget {
  final String? artPath;
  final double size;

  const ArtThumbnail({super.key, this.artPath, this.size = 48});

  @override
  Widget build(BuildContext context) {
    if (artPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(artPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(Icons.album, color: Colors.grey[600], size: size * 0.5),
      );
}
