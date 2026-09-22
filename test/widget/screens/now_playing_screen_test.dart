import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/screens/now_playing_screen.dart';
import '../../helpers/fake_player_service.dart';

void main() {
  testWidgets('shows the play icon once the queue finishes playing',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakePlayerService();

    await tester
        .pumpWidget(MaterialApp(home: NowPlayingScreen(playerService: fake)));

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
    // Regression: this screen used to only render once sequenceStateStream
    // had a loaded source, so opening it during a download wait showed a
    // blank screen instead of the buffering spinner.
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakePlayerService();
    final release = Release(
      folderPath: '/music/Test',
      name: 'Test',
      tracks: const [
        Track(path: '/music/Test/01.mp3', title: 'Track One', trackNumber: 1)
      ],
      tags: const [],
    );

    await tester
        .pumpWidget(MaterialApp(home: NowPlayingScreen(playerService: fake)));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Track One'), findsNothing);

    await fake.playRelease(release);
    fake.emitWaitingForDownload(true);
    await tester.pump();
    await tester.pump();

    expect(find.text('Track One'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // The spinner replaces the play/pause button itself, not an overlay.
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byIcon(Icons.pause), findsNothing);

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
      'switching to a track in another release shows its title, artist and album immediately, not the previous track\'s',
      (tester) async {
    // Regression: title/artist/album fell back to the just_audio-loaded tag
    // whenever one was present, even if it was still the *previous*
    // track's tag (because the newly requested track hadn't finished
    // downloading and loading yet) — only the art (read straight from
    // currentRelease) updated immediately.
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakePlayerService();
    final releaseOne = Release(
      folderPath: '/music/One',
      name: 'Release One',
      albumArtist: 'Old Artist',
      tracks: const [
        Track(path: '/music/One/01.mp3', title: 'Old Track', trackNumber: 1)
      ],
      tags: const [],
    );
    final releaseTwo = Release(
      folderPath: '/music/Two',
      name: 'Release Two',
      albumTitle: 'Album Two',
      albumArtist: 'New Artist',
      tracks: const [
        Track(path: '/music/Two/01.mp3', title: 'New Track', trackNumber: 1)
      ],
      tags: const [],
    );

    await tester
        .pumpWidget(MaterialApp(home: NowPlayingScreen(playerService: fake)));

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
    expect(find.text('New Artist'), findsOneWidget);
    expect(find.text('Album Two'), findsOneWidget);
    expect(find.text('Old Track'), findsNothing);
    expect(find.text('Old Artist'), findsNothing);
  });

  testWidgets('swiping down dismisses the screen', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakePlayerService();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => NowPlayingScreen(playerService: fake)),
              ),
              child: const Text('Library'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    fake.emitSequenceState(const MediaItem(id: '1', title: 'Track One'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(NowPlayingScreen), findsOneWidget);

    await tester.fling(
        find.byKey(const Key('now-playing-dismiss-area')),
        const Offset(0, 300),
        1000);
    await tester.pumpAndSettle();

    expect(find.byType(NowPlayingScreen), findsNothing);
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('swiping up does not dismiss the screen', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakePlayerService();

    await tester
        .pumpWidget(MaterialApp(home: NowPlayingScreen(playerService: fake)));

    fake.emitSequenceState(const MediaItem(id: '1', title: 'Track One'));
    await tester.pump();

    await tester.fling(
        find.byKey(const Key('now-playing-dismiss-area')),
        const Offset(0, -300),
        1000);
    await tester.pumpAndSettle();

    expect(find.byType(NowPlayingScreen), findsOneWidget);
  });
}
