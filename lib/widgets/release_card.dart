import 'package:flutter/material.dart';
import '../models/release.dart';

class ReleaseCard extends StatelessWidget {
  final Release release;
  final VoidCallback onTap;

  const ReleaseCard({super.key, required this.release, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(release.name),
      subtitle: release.tags.isNotEmpty
          ? Wrap(
              spacing: 4,
              children: release.tags
                  .map((t) => Chip(
                        label: Text(t, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            )
          : Text('${release.tracks.length} tracks',
              style: const TextStyle(color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
