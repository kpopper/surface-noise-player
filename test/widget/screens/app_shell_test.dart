import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:surface_noise_player/screens/app_shell.dart';
import 'package:surface_noise_player/services/library_provider.dart';
import '../../helpers/fake_bookmark_service.dart';
import '../../helpers/fake_library_service.dart';
import '../../helpers/fake_player_service.dart';

void main() {
  testWidgets('shows a SnackBar when the player reports an error message', (tester) async {
    final fakePlayer = FakePlayerService();
    final provider = LibraryProvider(FakeLibraryService(), FakeBookmarkService());

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryProvider>.value(
        value: provider,
        child: MaterialApp(home: AppShell(playerService: fakePlayer)),
      ),
    );
    await tester.pumpAndSettle();

    fakePlayer.emitErrorMessage("Couldn't play 'Track One' — check it's downloaded from iCloud.");
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't play 'Track One' — check it's downloaded from iCloud."), findsOneWidget);
  });
}
