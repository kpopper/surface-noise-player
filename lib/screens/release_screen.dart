import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import '../models/release.dart';
import '../services/abstract_player_service.dart';
import '../services/bookmark_service.dart';
import '../services/library_provider.dart';
import '../services/player_service.dart';
import '../widgets/tag_chip.dart';

class ReleaseScreen extends StatefulWidget {
  final Release release;
  final AbstractPlayerService? playerService;
  final BookmarkService? bookmarkService;
  const ReleaseScreen({
    super.key,
    required this.release,
    this.playerService,
    this.bookmarkService,
  });

  @override
  State<ReleaseScreen> createState() => _ReleaseScreenState();
}

class _ReleaseScreenState extends State<ReleaseScreen> {
  late Release _release;
  late AbstractPlayerService _playerSvc;
  late BookmarkService _bookmarks;
  final _tagController = TextEditingController();
  Set<String> _unavailablePaths = {};

  @override
  void initState() {
    super.initState();
    _release = widget.release;
    _playerSvc = widget.playerService ?? PlayerService.instance;
    _bookmarks = widget.bookmarkService ?? BookmarkService.instance;
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    final results = await Future.wait(
      _release.tracks.map((t) => _bookmarks.isFileAvailable(t.path)),
    );
    if (!mounted) return;
    setState(() {
      _unavailablePaths = {
        for (var i = 0; i < _release.tracks.length; i++)
          if (!results[i]) _release.tracks[i].path,
      };
    });
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _addTag(String tag) async {
    if (tag.trim().isEmpty) return;
    final lib = context.read<LibraryProvider>();
    await lib.addTagToRelease(_release, tag.trim().toLowerCase());
    // Refresh local state from provider
    final updated =
        lib.allReleases.firstWhere((r) => r.folderPath == _release.folderPath);
    setState(() => _release = updated);
    _tagController.clear();
  }

  Future<void> _removeTag(String tag) async {
    final lib = context.read<LibraryProvider>();
    await lib.removeTagFromRelease(_release, tag);
    final updated =
        lib.allReleases.firstWhere((r) => r.folderPath == _release.folderPath);
    setState(() => _release = updated);
  }

  void _showAddTagDialog() {
    showModalBottomSheet(
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
            FutureBuilder<List<String>>(
              future: context.read<LibraryProvider>().allTags(),
              builder: (context, snap) {
                final existing = (snap.data ?? [])
                    .where((t) => !_release.tags.contains(t))
                    .toList();
                if (existing.isNotEmpty) {
                  return Wrap(
                    spacing: 8,
                    children: existing
                        .map((t) => ActionChip(
                              label: Text(t),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _addTag(t);
                              },
                            ))
                        .toList(),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'New tag…',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _addTag(_tagController.text);
                  },
                ),
              ),
              onSubmitted: (v) {
                Navigator.pop(ctx);
                _addTag(v);
              },
              textCapitalization: TextCapitalization.none,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_release.name)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<SequenceState?>(
              stream: _playerSvc.sequenceStateStream,
              builder: (context, snap) {
                // currentTrack is set as soon as a track is requested, even
                // before it's downloaded and handed to just_audio — fall
                // back to it (refreshed via waitingForDownloadStream below)
                // so the row highlights immediately on tap, not only once
                // the track actually starts playing.
                final tag = snap.data?.currentSource?.tag as MediaItem?;
                final isThisRelease = _playerSvc.currentRelease?.folderPath ==
                    _release.folderPath;

                return StreamBuilder<bool>(
                  stream: _playerSvc.waitingForDownloadStream,
                  initialData: _playerSvc.isWaitingForDownload,
                  builder: (context, waitingSnap) {
                    final currentPath = tag?.id ??
                        (isThisRelease ? _playerSvc.currentTrack?.path : null);
                    final isWaiting = waitingSnap.data ?? false;

                    return ListView(
                      children: [
                        if (_release.artPath != null)
                          Image.file(
                            File(_release.artPath!),
                            width: double.infinity,
                            fit: BoxFit.fitWidth,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    ..._release.tags.map((t) => TagChip(
                                          label: t,
                                          onDeleted: () => _removeTag(t),
                                        )),
                                    ActionChip(
                                      avatar: const Icon(Icons.add, size: 16),
                                      label: const Text('Add tag'),
                                      onPressed: _showAddTagDialog,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                        ...List.generate(_release.tracks.length, (i) {
                          final track = _release.tracks[i];
                          final isPlaying =
                              isThisRelease && currentPath == track.path;
                          // Not yet downloaded locally — still tappable; playing it
                          // triggers a download and waits for it (see PlayerService).
                          final isUnavailable =
                              _unavailablePaths.contains(track.path);
                          return ListTile(
                            leading: isPlaying && isWaiting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : isPlaying
                                    ? const Icon(Icons.equalizer,
                                        color: Colors.deepOrange)
                                    : isUnavailable
                                        ? Icon(Icons.cloud_download_outlined,
                                            color: Colors.grey[500], size: 20)
                                        : Text('${track.trackNumber}',
                                            style: const TextStyle(
                                                color: Colors.grey)),
                            title: Text(
                              track.title,
                              style: TextStyle(
                                fontWeight: isPlaying
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isPlaying ? Colors.deepOrange : null,
                              ),
                            ),
                            subtitle: track.artist != null
                                ? Text(track.artist!,
                                    style: const TextStyle(fontSize: 12))
                                : null,
                            onTap: () => _playerSvc.playTrack(_release, i),
                          );
                        }),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play all'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () => _playerSvc.playRelease(_release),
            ),
          ),
        ],
      ),
    );
  }
}
