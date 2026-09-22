import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/library_provider.dart';
import 'tag_chip.dart';

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

            return SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  ...sorted.map((t) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: TagChip(
                          label: t,
                          selected: active.contains(t),
                          onTap: () => lib.toggleTag(t),
                        ),
                      )),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
