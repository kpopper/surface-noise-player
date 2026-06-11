import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surface_noise_player/widgets/tag_chip.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('TagChip — deletable mode (onDeleted provided)', () {
    testWidgets('displays the label', (tester) async {
      await tester.pumpWidget(wrap(const TagChip(label: 'jazz', onDeleted: null)));
      // null onDeleted → FilterChip path, still shows label
      expect(find.text('jazz'), findsOneWidget);
    });

    testWidgets('shows delete icon when onDeleted is set', (tester) async {
      await tester.pumpWidget(wrap(TagChip(label: 'jazz', onDeleted: () {})));
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('calls onDeleted when delete icon is tapped', (tester) async {
      bool deleted = false;
      await tester.pumpWidget(wrap(TagChip(label: 'jazz', onDeleted: () => deleted = true)));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(deleted, isTrue);
    });
  });

  group('TagChip — filter mode (no onDeleted)', () {
    testWidgets('renders as FilterChip', (tester) async {
      await tester.pumpWidget(wrap(TagChip(label: 'rock', onTap: () {})));
      expect(find.byType(FilterChip), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(wrap(TagChip(label: 'rock', onTap: () => tapped = true)));
      await tester.tap(find.text('rock'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('selected state is reflected', (tester) async {
      await tester.pumpWidget(
        wrap(TagChip(label: 'vinyl', selected: true, onTap: () {})),
      );
      final chip = tester.widget<FilterChip>(find.byType(FilterChip));
      expect(chip.selected, isTrue);
    });

    testWidgets('unselected by default', (tester) async {
      await tester.pumpWidget(wrap(TagChip(label: 'vinyl', onTap: () {})));
      final chip = tester.widget<FilterChip>(find.byType(FilterChip));
      expect(chip.selected, isFalse);
    });
  });
}
