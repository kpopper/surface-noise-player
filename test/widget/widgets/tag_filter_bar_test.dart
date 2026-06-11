import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:surface_noise_player/services/library_provider.dart';
import 'package:surface_noise_player/widgets/tag_chip.dart';
import 'package:surface_noise_player/widgets/tag_filter_bar.dart';
import '../../helpers/fake_library_service.dart';

Widget wrapWithProvider(LibraryProvider provider) => ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: const MaterialApp(home: Scaffold(body: TagFilterBar())),
    );

Future<LibraryProvider> buildProvider({
  List<String> tags = const [],
  List<String> activeTags = const [],
}) async {
  final fake = FakeLibraryService()..tagsToReturn = tags;
  final provider = LibraryProvider(fake);
  for (final t in activeTags) {
    provider.toggleTag(t);
  }
  return provider;
}

void main() {
  testWidgets('renders nothing when there are no tags', (tester) async {
    final provider = await buildProvider();
    await tester.pumpWidget(wrapWithProvider(provider));
    await tester.pump(); // settle FutureBuilder
    expect(find.byType(TagChip), findsNothing);
  });

  testWidgets('renders a chip for each tag', (tester) async {
    final provider = await buildProvider(tags: ['jazz', 'rock', 'vinyl']);
    await tester.pumpWidget(wrapWithProvider(provider));
    await tester.pump();
    expect(find.text('jazz'), findsOneWidget);
    expect(find.text('rock'), findsOneWidget);
    expect(find.text('vinyl'), findsOneWidget);
  });

  testWidgets('shows Clear chip when a tag is active', (tester) async {
    final provider = await buildProvider(tags: ['jazz'], activeTags: ['jazz']);
    await tester.pumpWidget(wrapWithProvider(provider));
    await tester.pump();
    expect(find.text('Clear'), findsOneWidget);
  });

  testWidgets('does not show Clear chip when no tags are active', (tester) async {
    final provider = await buildProvider(tags: ['jazz']);
    await tester.pumpWidget(wrapWithProvider(provider));
    await tester.pump();
    expect(find.text('Clear'), findsNothing);
  });

  testWidgets('tapping a chip calls toggleTag on the provider', (tester) async {
    final provider = await buildProvider(tags: ['jazz']);
    await tester.pumpWidget(wrapWithProvider(provider));
    await tester.pump();

    await tester.tap(find.text('jazz'));
    await tester.pump();

    expect(provider.activeTags, contains('jazz'));
  });

  testWidgets('tapping Clear calls clearTagFilter', (tester) async {
    final provider = await buildProvider(tags: ['jazz'], activeTags: ['jazz']);
    await tester.pumpWidget(wrapWithProvider(provider));
    await tester.pump();

    await tester.tap(find.text('Clear'));
    await tester.pump();

    expect(provider.activeTags, isEmpty);
  });
}
