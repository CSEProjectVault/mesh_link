import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_link/main.dart';

void main() {
  testWidgets('shows the login screen when no session exists',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MeshLinkApp());

    expect(find.text('MeshLink'), findsOneWidget);
    expect(find.text('Organization'), findsOneWidget);
    expect(find.text('Join a trip'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });
}
