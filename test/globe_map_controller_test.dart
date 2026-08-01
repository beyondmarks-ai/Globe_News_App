import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/globe_map_controller.dart';
import 'package:globe_news_beta/place_search/place_search_result.dart';

void main() {
  test('rotation can be suspended for an overlay and resumed safely', () {
    final controller = GlobeMapController();
    addTearDown(controller.dispose);

    controller.setRotationSuspended(true);
    expect(controller.isRotationSuspended, isTrue);

    controller.setRotationSuspended(false);
    expect(controller.isRotationSuspended, isFalse);
  });
  test(
    'search fly-to disables auto rotation even before a map is attached',
    () async {
      final controller = GlobeMapController();
      addTearDown(controller.dispose);

      await controller.flyToPlace(
        const PlaceSearchResult(
          name: 'Bengaluru',
          longitude: 77.5946,
          latitude: 12.9716,
          featureType: 'place',
        ),
      );

      expect(controller.isAutoRotationDisabledForSession, isTrue);
    },
  );
  test('auto rotation stays disabled for the remainder of the session', () {
    final controller = GlobeMapController();
    addTearDown(controller.dispose);

    controller.disableAutoRotationForSession();
    expect(controller.isAutoRotationDisabledForSession, isTrue);

    controller.setRotationSuspended(true);
    controller.setRotationSuspended(false);
    expect(controller.isAutoRotationDisabledForSession, isTrue);
  });
}
