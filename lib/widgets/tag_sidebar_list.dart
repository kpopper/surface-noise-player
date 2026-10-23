import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/library_provider.dart';
import '../utils/tag_colors.dart';
import 'floating_player.dart';

// The wide layout's tag filters: every tag as a vertical list, toggled by
// clicking, with active ones highlighted in their tag colour. The phone
// layout's equivalent is TagFilterBar.
class TagSidebarList extends StatelessWidget {
  final ValueChanged<String>? onTagToggled;
  const TagSidebarList({super.key, this.onTagToggled});

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, lib, _) {
        return FutureBuilder<List<String>>(
          future: lib.allTags(),
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            const untaggedTag = 'untagged';
            final untaggedActive = lib.untaggedActive;
            final tags = snap.data!;
            if (tags.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child:
                    Text('No tags yet', style: TextStyle(color: Colors.grey)),
              );
            }
            final active = lib.activeTags;
            return ListView(
              // Lets the last tags scroll clear of the floating player.
              padding:
                  const EdgeInsets.fromLTRB(8, 0, 8, kFloatingPlayerClearance),
              children: [
                for (final tag in tags)
                  _TagRow(
                    tag: tag,
                    selected: active.contains(tag),
                    onTap: () {
                      lib.toggleTag(tag);
                      onTagToggled?.call(tag);
                    },
                  ),
                _TagRow(
                    tag: untaggedTag,
                    selected: untaggedActive,
                    onTap: () {
                      lib.toggleUntagged();
                      onTagToggled?.call(untaggedTag);
                    }),
              ],
            );
          },
        );
      },
    );
  }
}

class _TagRow extends StatelessWidget {
  final String tag;
  final bool selected;
  final VoidCallback onTap;

  const _TagRow(
      {required this.tag, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = tagColor(tag);
    return ListTile(
      dense: true,
      selected: selected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      selectedTileColor: color.withValues(alpha: 0.18),
      leading: Icon(Icons.circle, size: 10, color: color),
      minLeadingWidth: 10,
      title: Text(
        tag,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      trailing: selected ? Icon(Icons.close, size: 16, color: color) : null,
      onTap: onTap,
    );
  }
}
