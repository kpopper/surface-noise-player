import 'dart:io';
import 'package:flutter/material.dart';

class ArtThumbnail extends StatelessWidget {
  final String? artPath;
  final double size;
  // Shows a spinner over the artwork, e.g. while waiting for the next
  // track to finish downloading from iCloud before playback can resume.
  final bool loading;

  const ArtThumbnail({super.key, this.artPath, this.size = 48, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final art = artPath != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(artPath!),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(),
            ),
          )
        : _placeholder();

    if (!loading) return art;

    return Stack(
      alignment: Alignment.center,
      children: [
        art,
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        SizedBox(
          width: size * 0.35,
          height: size * 0.35,
          child: const CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
        ),
      ],
    );
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
