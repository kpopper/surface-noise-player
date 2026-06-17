import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/library_provider.dart';
import '../widgets/release_card.dart';
import '../widgets/tag_filter_bar.dart';
import 'library_management_screen.dart';
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

  void _openManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LibraryManagementScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Surface Noise'),
        actions: [
          IconButton(
            icon: const Icon(Icons.library_add),
            tooltip: 'Manage library',
            onPressed: _openManagement,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh library',
            onPressed: () => context.read<LibraryProvider>().refresh(),
          ),
        ],
      ),
      body: Consumer<LibraryProvider>(
        builder: (context, lib, _) {
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
                    icon: const Icon(Icons.library_add),
                    label: const Text('Set up Library'),
                    onPressed: _openManagement,
                  ),
                ],
              ),
            );
          }

          if (lib.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          final releases = lib.releases;

          if (releases.isEmpty && lib.activeTags.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.album, size: 72, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No albums selected',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.library_add),
                    label: const Text('Manage Library'),
                    onPressed: _openManagement,
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
        },
      ),
    );
  }
}
