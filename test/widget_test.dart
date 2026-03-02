import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:esep/app.dart';

void main() {
  testWidgets('EsepApp renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: EsepApp(),
      ),
    );

    // Verify the app renders the title
    expect(find.text('Есеп'), findsWidgets);
  });
}
