import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/widgets/form_components.dart';

void main() {
  testWidgets('sheet follows steps that swap scrolling and fixed content', (
    tester,
  ) async {
    // An iPhone 16 Pro Max with its notch and home indicator insets.
    const size = Size(440, 956);
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = size * 3;
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    // Like the collage setup: a short scrolling selection, a crop step that
    // fills the sheet without a scroll view, then a long scrolling review.
    final step = ValueNotifier('select');
    addTearDown(step.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFormSheet<void>(
                context: context,
                enableDrag: false,
                builder: (_) => ValueListenableBuilder(
                  valueListenable: step,
                  builder: (_, value, _) => switch (value) {
                    'crop' => FormSheet(
                      title: 'Crop',
                      scrollable: false,
                      footer: const Text('Next'),
                      child: LayoutBuilder(
                        builder: (_, constraints) =>
                            SizedBox(height: constraints.maxHeight),
                      ),
                    ),
                    'review' => const FormSheet(
                      title: 'Review',
                      footer: Text('Next'),
                      child: Column(
                        children: [SizedBox(height: 1200), Text('Save')],
                      ),
                    ),
                    _ => const FormSheet(title: 'Select', child: Text('Pick')),
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    Rect sheet() => tester.getRect(find.byType(FractionallySizedBox).last);
    final select = sheet();

    step.value = 'crop';
    await tester.pumpAndSettle();
    final crop = sheet();
    expect(crop.top, lessThan(select.top));
    expect(tester.getRect(find.text('Next')).bottom, lessThan(crop.bottom));

    step.value = 'review';
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(sheet().top, closeTo(crop.top, 1));
    expect(tester.getRect(find.text('Save')).bottom, lessThan(sheet().bottom));

    step.value = 'select';
    await tester.pumpAndSettle();
    expect(sheet().top, closeTo(select.top, 1));
  });
}
