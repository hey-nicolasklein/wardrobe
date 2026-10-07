import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/widgets/form_components.dart';

void main() {
  testWidgets('sheet follows a step that swaps in non-scrolling content', (
    tester,
  ) async {
    const size = Size(393, 852);
    final cropping = ValueNotifier(false);
    addTearDown(cropping.dispose);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFormSheet<void>(
                context: context,
                enableDrag: false,
                // Like the collage setup: a short scrolling step, then a
                // crop step that fills the sheet without a scroll view.
                builder: (_) => ValueListenableBuilder(
                  valueListenable: cropping,
                  builder: (_, crop, _) => crop
                      ? const FormSheet(
                          title: 'Crop',
                          scrollable: false,
                          footer: Text('Next'),
                          child: Column(
                            children: [Expanded(child: Placeholder())],
                          ),
                        )
                      : const FormSheet(title: 'Select', child: Text('Pick')),
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

    cropping.value = true;
    await tester.pumpAndSettle();
    final crop = sheet();
    expect(crop.top, lessThan(select.top));
    expect(tester.getRect(find.text('Next')).bottom, lessThan(crop.bottom));

    cropping.value = false;
    await tester.pumpAndSettle();
    expect(sheet().top, closeTo(select.top, 1));
  });
}
