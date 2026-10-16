import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/library_provider.dart';

class LibrarySearchField extends StatefulWidget {
  // Lets the ⌘F shortcut (see AppShell) move focus here.
  final FocusNode? focusNode;
  // Smaller text, icons and height, to sit in the wide layout's nav bar.
  final bool compact;
  const LibrarySearchField({super.key, this.focusNode, this.compact = false});

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
    final compact = widget.compact;
    final iconSize = compact ? 18.0 : null;
    // Icons stay centred in a box the field's height, not the default 48.
    final iconConstraints =
        compact ? const BoxConstraints.tightFor(width: 32, height: 32) : null;
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      style: compact ? const TextStyle(fontSize: 13) : null,
      decoration: InputDecoration(
        hintText: 'Search artist or album…',
        prefixIcon: Icon(Icons.search, size: iconSize),
        prefixIconConstraints: iconConstraints,
        isDense: true,
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8)
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        suffixIcon: lib.searchQuery.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.clear, size: iconSize),
                constraints: iconConstraints,
                padding: compact ? EdgeInsets.zero : null,
                tooltip: 'Clear search',
                onPressed: () {
                  _controller.clear();
                  lib.setSearchQuery('');
                },
              ),
      ),
      onChanged: lib.setSearchQuery,
    );
  }
}
