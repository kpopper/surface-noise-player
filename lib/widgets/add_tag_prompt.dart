import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/release.dart';
import '../services/library_provider.dart';
import '../utils/layout.dart';

// Prompts for a tag to add to [release] — picked from existing tags or typed
// as a new one. A bottom sheet on phone-sized layouts, a dialog on the wide
// layout where a sheet spanning the whole window would look out of place.
Future<void> showAddTagPrompt(BuildContext context, Release release) async {
  final lib = context.read<LibraryProvider>();
  final tagsFuture = lib.allTags();
  final String? tag;
  if (isWideLayout(context)) {
    tag = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add tag'),
        content: SizedBox(
          width: 400,
          child: _AddTagForm(release: release, tagsFuture: tagsFuture),
        ),
      ),
    );
  } else {
    tag = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add tag',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _AddTagForm(release: release, tagsFuture: tagsFuture),
          ],
        ),
      ),
    );
  }
  if (tag == null || tag.trim().isEmpty) return;
  await lib.addTagToRelease(release, tag.trim().toLowerCase());
}

// Pops the enclosing sheet/dialog with the chosen tag.
class _AddTagForm extends StatefulWidget {
  final Release release;
  final Future<List<String>> tagsFuture;
  const _AddTagForm({required this.release, required this.tagsFuture});

  @override
  State<_AddTagForm> createState() => _AddTagFormState();
}

class _AddTagFormState extends State<_AddTagForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _choose(String tag) => Navigator.pop(context, tag);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<String>>(
          future: widget.tagsFuture,
          builder: (context, snap) {
            final existing = (snap.data ?? [])
                .where((t) => !widget.release.tags.contains(t))
                .toList();
            if (existing.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                children: existing
                    .map((t) => ActionChip(
                          label: Text(t),
                          onPressed: () => _choose(t),
                        ))
                    .toList(),
              ),
            );
          },
        ),
        TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'New tag…',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _choose(_controller.text),
            ),
          ),
          onSubmitted: _choose,
          textCapitalization: TextCapitalization.none,
        ),
      ],
    );
  }
}
