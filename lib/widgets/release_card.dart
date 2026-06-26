import 'package:flutter/material.dart';
import '../models/release.dart';
import '../utils/tag_colors.dart';
import 'art_thumbnail.dart';

class ReleaseCard extends StatelessWidget {
  final Release release;
  final VoidCallback? onTap;

  const ReleaseCard({super.key, required this.release, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ArtThumbnail(artPath: release.artPath, size: 62),
      title: Text(release.name),
      subtitle: release.tags.isNotEmpty
          ? Text.rich(
              TextSpan(
                children: [
                  for (int i = 0; i < release.tags.length; i++) ...[
                    if (i > 0)
                      const TextSpan(
                        text: ' · ',
                        style: TextStyle(color: Colors.grey),
                      ),
                    TextSpan(
                      text: release.tags[i],
                      style: TextStyle(color: tagColor(release.tags[i])),
                    ),
                  ],
                ],
              ),
            )
          : Text('${release.tracks.length} tracks',
              style: const TextStyle(color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
