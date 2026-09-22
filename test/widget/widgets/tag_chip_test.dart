import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surface_noise_player/widgets/tag_chip.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('TagChip — deletable mode (onDeleted provided)', () {
    testWidgets('displays the label', (tester) async {
      await tester
          .pumpWidget(wrap(const TagChip(label: 'jazz', onDeleted: null)));
      // null onDeleted → FilterChip path, still shows label
      expect(find.text('jazz'), findsOneWidget);
    });

    testWidgets('shows delete icon when onDeleted is set', (tester) async {
      await tester.pumpWidget(wrap(TagChip(label: 'jazz', onDeleted: () {})));
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('calls onDeleted when delete icon is tapped', (tester) async {
      bool deleted = false;
      await tester.pumpWidget(
          wrap(TagChip(label: 'jazz', onDeleted: () => deleted = true)));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(deleted, isTrue);
    });

    testWidgets('label text is bold', (tester) async {
      await tester.pumpWidget(wrap(TagChip(label: 'jazz', onDeleted: () {})));
      final text = tester.widget<Text>(find.text('jazz'));
      expect(text.style?.fontWeight, FontWeight.bold);
    });
  });

  group('TagChip — filter mode (no onDeleted)', () {
    testWidgets('renders as InputChip', (tester) async {
      await tester.pumpWidget(wrap(TagChip(label: 'rock', onTap: () {})));
      expect(find.byType(InputChip), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;
      await tester
          .pumpWidget(wrap(TagChip(label: 'rock', onTap: () => tapped = true)));
      await tester.tap(find.text('rock'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('selected state is reflected', (tester) async {
      await tester.pumpWidget(
        wrap(TagChip(label: 'vinyl', selected: true, onTap: () {})),
      );
      final chip = tester.widget<InputChip>(find.byType(InputChip));
      expect(chip.selected, isTrue);
    });

    testWidgets('unselected by default', (tester) async {
      await tester.pumpWidget(wrap(TagChip(label: 'vinyl', onTap: () {})));
      final chip = tester.widget<InputChip>(find.byType(InputChip));
      expect(chip.selected, isFalse);
    });

    testWidgets('label text is bold', (tester) async {
      await tester.pumpWidget(wrap(TagChip(label: 'rock', onTap: () {})));
      final text = tester.widget<Text>(find.text('rock'));
      expect(text.style?.fontWeight, FontWeight.bold);
    });

    testWidgets('no delete icon when unselected', (tester) async {
      await tester.pumpWidget(wrap(TagChip(label: 'vinyl', onTap: () {})));
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('shows delete icon when selected', (tester) async {
      await tester.pumpWidget(
        wrap(TagChip(label: 'vinyl', selected: true, onTap: () {})),
      );
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('tapping delete icon when selected calls onTap',
        (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        wrap(TagChip(
          label: 'vinyl',
          selected: true,
          onTap: () => tapped = true,
        )),
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });
}
