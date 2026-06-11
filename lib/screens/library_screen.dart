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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Surface Noise'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Change music folder',
            onPressed: () => context.read<LibraryProvider>().pickFolder(),
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
                  const Text('No music folder selected',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose folder from iCloud Drive'),
                    onPressed: () => lib.pickFolder(),
                  ),
                ],
              ),
            );
          }

          if (lib.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          final releases = lib.releases;

          return Column(
            children: [
              const TagFilterBar(),
              if (releases.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      lib.activeTags.isEmpty
                          ? 'No releases found in folder'
                          : 'No releases match the selected tags',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: releases.length,
                    itemBuilder: (context, i) => ReleaseCard(
                      release: releases[i],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReleaseScreen(release: releases[i]),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
