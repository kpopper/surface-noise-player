import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/library_provider.dart';

class LibrarySearchField extends StatefulWidget {
  const LibrarySearchField({super.key});

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
                },
              ),
      ),
      onChanged: lib.setSearchQuery,
    );
  }
}
