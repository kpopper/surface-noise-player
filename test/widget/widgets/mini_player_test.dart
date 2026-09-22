import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/widgets/mini_player.dart';
import '../../helpers/fake_player_service.dart';

void main() {
  testWidgets('shows the play icon once the queue finishes playing',
      (tester) async {
    final fake = FakePlayerService();

    await tester.pumpWidget(MaterialApp(home: MiniPlayer(playerService: fake)));

    fake.emitSequenceState(const MediaItem(id: '1', title: 'Track One'));
    fake.emitPlayerState(
        playing: true, processingState: ProcessingState.completed);
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets(
      'appears with a spinner as soon as a track is requested, before just_audio has loaded it',
      (tester) async {
    // Regression: the mini player used to only appear once
    // sequenceStateStream had a loaded source, which meant it (and its
    // spinner) stayed invisible for the whole download-wait window —
    // nothing visibly happened when a track was tapped. It must show up
    // from currentRelease/currentTrack alone.
    final fake = FakePlayerService();
    final release = Release(
      folderPath: '/music/Test',
      name: 'Test',
      tracks: const [
        Track(path: '/music/Test/01.mp3', title: 'Track One', trackNumber: 1)
      ],
      tags: const [],
    );

    await tester.pumpWidget(MaterialApp(home: MiniPlayer(playerService: fake)));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Track One'), findsNothing);

    await fake.playRelease(release);
    fake.emitWaitingForDownload(true);
    await tester.pump();
    await tester.pump();

    expect(find.text('Track One'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // The spinner replaces the play/pause button itself, not an overlay —
    // neither icon should be present while waiting.
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byIcon(Icons.pause), findsNothing);

    // Once just_audio actually loads the track, the spinner clears and the
    // loaded MediaItem's own title takes over from the placeholder.
    fake.emitWaitingForDownload(false);
    fake.emitSequenceState(
        const MediaItem(id: '/music/Test/01.mp3', title: 'Track One'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Track One'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets(
      'switching to a track in another release shows its title and album immediately, not the previous track\'s',
      (tester) async {
    // Regression: title/album fell back to the just_audio-loaded tag
    // whenever one was present, even if it was still the *previous*
    // track's tag (because the newly requested track hadn't finished
    // downloading and loading yet) — only the art (read straight from
    // currentRelease) updated immediately; title/album stayed stuck on the
    // old track until the new one actually loaded.
    final fake = FakePlayerService();
    final releaseOne = Release(
      folderPath: '/music/One',
      name: 'Release One',
      tracks: const [
        Track(path: '/music/One/01.mp3', title: 'Old Track', trackNumber: 1)
      ],
      tags: const [],
    );
    final releaseTwo = Release(
      folderPath: '/music/Two',
      name: 'Release Two',
      albumTitle: 'Album Two',
      tracks: const [
        Track(path: '/music/Two/01.mp3', title: 'New Track', trackNumber: 1)
      ],
      tags: const [],
    );

    await tester.pumpWidget(MaterialApp(home: MiniPlayer(playerService: fake)));

    await fake.playRelease(releaseOne);
    fake.emitSequenceState(
        const MediaItem(id: '/music/One/01.mp3', title: 'Old Track'));
    await tester.pump();
    expect(find.text('Old Track'), findsOneWidget);

    // Requesting a track in a different release updates currentRelease and
    // currentTrack synchronously, but just_audio's sequenceStateStream
    // still reports the old track's tag until the new one downloads.
    await fake.playRelease(releaseTwo);
    fake.emitWaitingForDownload(true);
    await tester.pump();
    await tester.pump();

    expect(find.text('New Track'), findsOneWidget);
    expect(find.text('Album Two'), findsOneWidget);
    expect(find.text('Old Track'), findsNothing);
  });

  testWidgets('swiping up on it opens the Now Playing screen, same as tapping',
      (tester) async {
    final fake = FakePlayerService();
    var tapped = false;

    await tester.pumpWidget(MaterialApp(
      home: MiniPlayer(playerService: fake, onTap: () => tapped = true),
    ));

    fake.emitSequenceState(const MediaItem(id: '1', title: 'Track One'));
    await tester.pump();

    await tester.fling(
        find.byType(MiniPlayer), const Offset(0, -300), 1000);
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('swiping down on it does not open the Now Playing screen',
      (tester) async {
    final fake = FakePlayerService();
    var tapped = false;

    await tester.pumpWidget(MaterialApp(
      home: MiniPlayer(playerService: fake, onTap: () => tapped = true),
    ));

    fake.emitSequenceState(const MediaItem(id: '1', title: 'Track One'));
    await tester.pump();

    await tester.fling(find.byType(MiniPlayer), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(tapped, isFalse);
  });
}
