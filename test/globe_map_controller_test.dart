import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/globe_map_controller.dart';

void main() {
  test('rotation can be suspended for an overlay and resumed safely', () {
    final controller = GlobeMapController();
    addTearDown(controller.dispose);

    controller.setRotationSuspended(true);
    expect(controller.isRotationSuspended, isTrue);

    controller.setRotationSuspended(false);
    expect(controller.isRotationSuspended, isFalse);
  });
}
