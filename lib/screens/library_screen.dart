import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/library_provider.dart';
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
          body: _buildBody(context, lib),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, LibraryProvider lib) {
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
    if (releases.isEmpty && lib.activeTags.isEmpty) {
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
                'No releases match the selected tags',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: releases.length,
              itemBuilder: (context, i) {
                final release = releases[i];
                return Opacity(
                  opacity: release.isAvailable ? 1.0 : 0.4,
                  child: ReleaseCard(
                    release: release,
                    onTap: release.isAvailable
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReleaseScreen(release: release),
                              ),
                            )
                        : null,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
