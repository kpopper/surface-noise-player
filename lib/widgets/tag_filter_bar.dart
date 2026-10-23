import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/library_provider.dart';
import 'tag_chip.dart';

const _untaggedLabel = 'untagged';

class TagFilterBar extends StatelessWidget {
  const TagFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, lib, _) {
        return FutureBuilder<List<String>>(
          future: lib.allTags(),
          builder: (context, snap) {
            final tags = snap.data ?? [];
            if (tags.isEmpty) return const SizedBox.shrink();

            final active = lib.activeTags;
            final sorted = [
              ...tags.where((t) => active.contains(t)),
              ...tags.where((t) => !active.contains(t)),
            ];

            Widget chip(String label, bool selected, VoidCallback onTap) =>
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child:
                      TagChip(label: label, selected: selected, onTap: onTap),
                );
            final untagged =
                chip(_untaggedLabel, lib.untaggedActive, lib.toggleUntagged);

            return SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  // Like the active tags, an active "untagged" filter moves
                  // to the front; otherwise it sits at the end.
                  if (lib.untaggedActive) untagged,
                  for (final t in sorted)
                    chip(t, active.contains(t), () => lib.toggleTag(t)),
                  if (!lib.untaggedActive) untagged,
                ],
              ),
            );
          },
        );
      },
    );
  }
}
