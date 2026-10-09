import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/library_provider.dart';

class LibrarySearchField extends StatefulWidget {
  // Lets the ⌘F shortcut (see AppShell) move focus here.
  final FocusNode? focusNode;
  // Called after the query is updated, on each keystroke or clear.
  final ValueChanged<String>? onChanged;
  const LibrarySearchField({super.key, this.focusNode, this.onChanged});

  @override
  State<LibrarySearchField> createState() => _LibrarySearchFieldState();
}

class _LibrarySearchFieldState extends State<LibrarySearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryProvider>();
    // Keeps the field in sync when the query is cleared elsewhere (e.g.
    // picking a different library folder) without fighting live typing.
    if (lib.searchQuery.isEmpty && _controller.text.isNotEmpty) {
      _controller.clear();
    }
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      decoration: InputDecoration(
        hintText: 'Search artist or album…',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        suffixIcon: lib.searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  lib.setSearchQuery('');
                  widget.onChanged?.call('');
                },
              ),
      ),
      onChanged: (value) {
        lib.setSearchQuery(value);
        widget.onChanged?.call(value);
      },
    );
  }
}
