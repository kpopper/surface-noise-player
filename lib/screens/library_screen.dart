import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/library_provider.dart';
import '../widgets/library_search_field.dart';
import '../widgets/release_card.dart';
import '../widgets/tag_filter_bar.dart';
import 'release_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryProvider>().init();
    });
  }

  void _pickFolder() => context.read<LibraryProvider>().pickFolder();

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, lib, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Surface Noise'),
            actions: [
              IconButton(
                icon: const Icon(Icons.folder_open),
                tooltip: 'Choose library folder',
                onPressed: lib.loading ? null : _pickFolder,
              ),
              if (lib.loading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh library',
                  onPressed: () => context.read<LibraryProvider>().refresh(),
                ),
            ],
          ),
          body: GestureDetector(
            // Tapping anywhere outside an interactive control (release cards
            // and the search field itself both handle their own taps first,
            // so this only fires on genuinely "away" taps) dismisses the
            // keyboard by moving focus off the search field.
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: _buildBody(context, lib),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, LibraryProvider lib) {
    // Blank until the initial database load resolves, rather than briefly
    // showing the no-root CTA while rootPath is still its unset default.
    if (!lib.initialized) {
      return const SizedBox.shrink();
    }

    if (lib.rootPath == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No library set up',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose Library Folder'),
              onPressed: _pickFolder,
            ),
          ],
        ),
      );
    }

    final releases = lib.releases;

    // Already-known releases stay visible and interactive while a sync runs
    // in the background (the app bar spinner is the sync indicator) — only
    // fall back to a full-screen spinner when there's genuinely nothing to
    // show yet, e.g. the very first sync after picking a new folder.
    if (releases.isEmpty && lib.activeTags.isEmpty && lib.searchQuery.isEmpty) {
      if (lib.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.album, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No releases found',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose a Different Folder'),
              onPressed: _pickFolder,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        const TagFilterBar(),
        if (releases.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'No releases match the current filters',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: releases.length,
              itemBuilder: (context, i) {
                final release = releases[i];
                return ReleaseCard(
                  release: release,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReleaseScreen(release: release),
                    ),
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              const Expanded(child: LibrarySearchField()),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(lib.sortMode == LibrarySortMode.recency
                    ? Icons.unfold_more
                    : Icons.sort_by_alpha),
                tooltip: lib.sortMode == LibrarySortMode.recency
                    ? 'Sorted by recent activity — tap to sort alphabetically'
                    : 'Sorted alphabetically — tap to sort by recent activity',
                onPressed: lib.toggleSortMode,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
