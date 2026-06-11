import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surface_noise_player/models/release.dart';
import 'package:surface_noise_player/widgets/release_card.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Release makeRelease({String name = 'My Album', List<String> tags = const [], int trackCount = 5}) {
  final tracks = List.generate(
    trackCount,
    (i) => Track(path: '/album/${i + 1}.mp3', title: 'Track ${i + 1}', trackNumber: i + 1),
  );
  return Release(folderPath: '/music/album', name: name, tracks: tracks, tags: tags);
}

void main() {
  testWidgets('displays the release name', (tester) async {
    await tester.pumpWidget(wrap(ReleaseCard(release: makeRelease(name: 'Dark Side'), onTap: () {})));
    expect(find.text('Dark Side'), findsOneWidget);
  });

  testWidgets('shows track count when no tags', (tester) async {
    await tester.pumpWidget(wrap(ReleaseCard(release: makeRelease(trackCount: 9), onTap: () {})));
    expect(find.textContaining('9'), findsWidgets);
  });

  testWidgets('shows tags as chips when tags are present', (tester) async {
    final release = makeRelease(tags: ['jazz', 'vinyl']);
    await tester.pumpWidget(wrap(ReleaseCard(release: release, onTap: () {})));
    expect(find.text('jazz'), findsOneWidget);
    expect(find.text('vinyl'), findsOneWidget);
  });

  testWidgets('does not show track count when tags are present', (tester) async {
    final release = makeRelease(tags: ['jazz'], trackCount: 7);
    await tester.pumpWidget(wrap(ReleaseCard(release: release, onTap: () {})));
    // subtitle shows tags, not "7 tracks"
    expect(find.textContaining('7 tracks'), findsNothing);
  });

  testWidgets('calls onTap when tapped', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(wrap(ReleaseCard(release: makeRelease(), onTap: () => tapped = true)));
    await tester.tap(find.byType(ListTile));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('shows a trailing chevron icon', (tester) async {
    await tester.pumpWidget(wrap(ReleaseCard(release: makeRelease(), onTap: () {})));
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });
}
