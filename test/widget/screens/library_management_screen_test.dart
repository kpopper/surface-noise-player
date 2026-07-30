import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:surface_noise_player/models/folder_info.dart';
import 'package:surface_noise_player/screens/library_management_screen.dart';
import 'package:surface_noise_player/services/library_provider.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_library_service.dart';

Widget wrapWithProvider(LibraryProvider provider) =>
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: const MaterialApp(home: LibraryManagementScreen()),
    );

Future<LibraryProvider> pumpManagementScreen(
  WidgetTester tester, {
  String? savedRoot,
  List<FolderInfo> folders = const [],
}) async {
  final fake = FakeLibraryService()
    ..rootToReturn = savedRoot
    ..foldersToReturn = folders;
  final provider = LibraryProvider(fake, FakeBookmarkService());
  await provider.init();
  await tester.pumpWidget(wrapWithProvider(provider));
  await tester.pumpAndSettle();
  return provider;
}

void main() {
  group('search', () {
    testWidgets('filters the folder list by name', (tester) async {
      await pumpManagementScreen(tester, savedRoot: '/music', folders: const [
        FolderInfo(path: '/music/Album A', name: 'Album A', isSelected: true),
        FolderInfo(path: '/music/Bootleg B', name: 'Bootleg B', isSelected: true),
      ]);

      expect(find.text('Album A'), findsOneWidget);
      expect(find.text('Bootleg B'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'boot');
      await tester.pumpAndSettle();

      expect(find.text('Album A'), findsNothing);
      expect(find.text('Bootleg B'), findsOneWidget);
    });

    testWidgets('shows empty state when nothing matches', (tester) async {
      await pumpManagementScreen(tester, savedRoot: '/music', folders: const [
        FolderInfo(path: '/music/Album A', name: 'Album A', isSelected: true),
      ]);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('No albums match your search'), findsOneWidget);
    });

    testWidgets('clearing search restores the full list', (tester) async {
      await pumpManagementScreen(tester, savedRoot: '/music', folders: const [
        FolderInfo(path: '/music/Album A', name: 'Album A', isSelected: true),
        FolderInfo(path: '/music/Bootleg B', name: 'Bootleg B', isSelected: true),
      ]);

      await tester.enterText(find.byType(TextField), 'boot');
      await tester.pumpAndSettle();
      expect(find.text('Album A'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.text('Album A'), findsOneWidget);
      expect(find.text('Bootleg B'), findsOneWidget);
    });

    testWidgets('scrolling the list dismisses the keyboard', (tester) async {
      final manyFolders = List.generate(
        30,
        (i) => FolderInfo(path: '/music/Album $i', name: 'Album $i', isSelected: true),
      );
      await pumpManagementScreen(tester, savedRoot: '/music', folders: manyFolders);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('tapping empty space below the list dismisses the keyboard', (tester) async {
      await pumpManagementScreen(tester, savedRoot: '/music', folders: const [
        FolderInfo(path: '/music/Album A', name: 'Album A', isSelected: true),
      ]);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);

      // Tap near the bottom of the (empty) list area, well below the single list item.
      final bottomOfList = tester.getBottomLeft(find.byType(ListView)).translate(50, -10);
      await tester.tapAt(bottomOfList);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
    });
  });

  group('selected/unselected styling', () {
    testWidgets('selected folder name is bold', (tester) async {
      await pumpManagementScreen(tester, savedRoot: '/music', folders: const [
        FolderInfo(path: '/music/Already In', name: 'Already In', isSelected: true),
      ]);

      final text = tester.widget<Text>(find.text('Already In'));
      expect(text.style?.fontWeight, FontWeight.bold);
    });

    testWidgets('unselected folder name is normal weight', (tester) async {
      await pumpManagementScreen(tester, savedRoot: '/music', folders: const [
        FolderInfo(path: '/music/Fresh Drop', name: 'Fresh Drop', isSelected: false),
      ]);

      final text = tester.widget<Text>(find.text('Fresh Drop'));
      expect(text.style?.fontWeight, FontWeight.normal);
    });
  });
}
