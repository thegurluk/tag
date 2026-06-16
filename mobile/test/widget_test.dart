import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/locations/locations_providers.dart';
import 'package:mobile/features/map/location_permission_controller.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('renders the mobile app shell', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLocationsProvider.overrideWith((ref) async => const []),
          currentPositionProvider.overrideWith((ref) async => null),
        ],
        child: const LocationAlertApp(),
      ),
    );

    await tester.pump();

    expect(find.text('0 aktif yol bildirimi'), findsOneWidget);
  });
}
