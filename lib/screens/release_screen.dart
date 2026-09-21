import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
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
  late AbstractPlayerService _playerSvc;
  late BookmarkService _bookmarks;
  final _tagController = TextEditingController();
  Set<String> _unavailablePaths = {};
  List<String> _lastCheckedTrackPaths = [];
  bool _closing = false;
  bool _rescanning = false;

  // Availability isn't part of the database — it's a live iCloud filesystem
  // property that can change in the background, independently of anything
  // LibraryProvider would notify about. Keeps running for as long as this
  // screen stays open, even once every track currently looks available:
  // eviction (see LibraryService) is only a request to iOS, which decides
  // if and when to actually reclaim the local copy — often not immediately,
  // especially right after this same process just read the file — so a
  // track can flip back to unavailable at any time with no signal we'd
  // otherwise catch. isFileAvailable is a cheap local filesystem check, not
  // a network call, so polling it continuously while one screen is open is
  // inexpensive.
  Timer? _availabilityPollTimer;

  @override
  void initState() {
    super.initState();
    _playerSvc = widget.playerService ?? PlayerService.instance;
    _bookmarks = widget.bookmarkService ?? BookmarkService.instance;
    // A single on-demand retry, not repeated while this screen stays open —
    // see LibraryProvider.retryArtworkIfMissing.
    if (widget.release.artPath == null) {
      unawaited(context
          .read<LibraryProvider>()
          .retryArtworkIfMissing(widget.release));
    }
  }

  // Re-checks availability whenever the live track list actually changes
  // (a new track appears, one goes away) rather than on every rebuild.
  void _maybeReloadAvailability(Release release) {
    final currentPaths = release.tracks.map((t) => t.path).toList();
    if (listEquals(currentPaths, _lastCheckedTrackPaths)) return;
    _lastCheckedTrackPaths = currentPaths;
    _loadAvailability(release);
  }

  Future<void> _loadAvailability(Release release) async {
    final results = await Future.wait(
      release.tracks.map((t) => _bookmarks.isFileAvailable(t.path)),
    );
    if (!mounted) return;
    setState(() {
      _unavailablePaths = {
        for (var i = 0; i < release.tracks.length; i++)
          if (!results[i]) release.tracks[i].path,
      };
    });
    _availabilityPollTimer ??=
        Timer.periodic(const Duration(seconds: 2), (_) => _pollAvailability());
  }

  void _pollAvailability() {
    if (!mounted) return;
    final matches = context
        .read<LibraryProvider>()
        .allReleases
        .where((r) => r.folderPath == widget.release.folderPath);
    if (matches.isEmpty) {
      return; // release vanished; build()'s auto-close handles this
    }
    _loadAvailability(matches.first);
  }

  // The release is no longer in the library (its folder disappeared in a
  // sync) — close this screen rather than leave a dead-end view open.
  // Guarded so a rebuild while still closing doesn't schedule a second pop.
  void _scheduleClose() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _availabilityPollTimer?.cancel();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _addTag(Release release, String tag) async {
    if (tag.trim().isEmpty) return;
    await context
        .read<LibraryProvider>()
        .addTagToRelease(release, tag.trim().toLowerCase());
    _tagController.clear();
  }

  Future<void> _removeTag(Release release, String tag) async {
    await context.read<LibraryProvider>().removeTagFromRelease(release, tag);
  }

  Future<void> _rescan(Release release) async {
    if (_rescanning) return;
    setState(() => _rescanning = true);
    try {
      await context.read<LibraryProvider>().rescanRelease(release);
    } finally {
      if (mounted) setState(() => _rescanning = false);
    }
  }

  void _showAddTagDialog(Release release) {
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
                    .where((t) => !release.tags.contains(t))
                    .toList();
                if (existing.isNotEmpty) {
                  return Wrap(
                    spacing: 8,
                    children: existing
                        .map((t) => ActionChip(
                              label: Text(t),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _addTag(release, t);
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
                    _addTag(release, _tagController.text);
                  },
                ),
              ),
              onSubmitted: (v) {
                Navigator.pop(ctx);
                _addTag(release, v);
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
    final lib = context.watch<LibraryProvider>();
    final matches =
        lib.allReleases.where((r) => r.folderPath == widget.release.folderPath);
    final release = matches.isEmpty ? null : matches.first;

    if (release == null) {
      _scheduleClose();
      return Scaffold(
        appBar: AppBar(title: Text(widget.release.name)),
        body: const SizedBox.shrink(),
      );
    }

    _maybeReloadAvailability(release);

    return Scaffold(
      appBar: AppBar(
        title: Text(release.name),
        actions: [
          if (_rescanning)
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
              tooltip: 'Rescan metadata',
              onPressed: () => _rescan(release),
            ),
        ],
      ),
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
                final isThisRelease =
                    _playerSvc.currentRelease?.folderPath == release.folderPath;

                return StreamBuilder<bool>(
                  stream: _playerSvc.waitingForDownloadStream,
                  initialData: _playerSvc.isWaitingForDownload,
                  builder: (context, waitingSnap) {
                    final currentPath = tag?.id ??
                        (isThisRelease ? _playerSvc.currentTrack?.path : null);
                    final isWaiting = waitingSnap.data ?? false;

                    if (release.tracks.isEmpty) {
                      return const Center(
                        child: Text(
                          'No tracks found yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    return ListView(
                      children: [
                        if (release.artPath != null)
                          Image.file(
                            File(release.artPath!),
                            // Bypasses Flutter's image cache, which is keyed
                            // by file path — without this, artwork that gets
                            // re-resolved at the same path (e.g. cover.jpg
                            // rewritten after a bad MusicBrainz match is
                            // cleared and retried) would keep showing
                            // whatever was cached for that path, not the new
                            // file's actual bytes.
                            key: ValueKey(release.artPath),
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
                                    ...release.tags.map((t) => TagChip(
                                          label: t,
                                          onDeleted: () =>
                                              _removeTag(release, t),
                                        )),
                                    ActionChip(
                                      avatar: const Icon(Icons.add, size: 16),
                                      label: const Text('Add tag'),
                                      onPressed: () =>
                                          _showAddTagDialog(release),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                        ...List.generate(release.tracks.length, (i) {
                          final track = release.tracks[i];
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
                            // Always render a subtitle line, even when
                            // there's no artist yet — otherwise the row's
                            // height changes (and the whole list jumps)
                            // right when a track's real metadata arrives
                            // and it suddenly gains one.
                            subtitle: Text(track.artist ?? '',
                                style: const TextStyle(fontSize: 12)),
                            onTap: () => _playerSvc.playTrack(release, i),
                          );
                        }),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
