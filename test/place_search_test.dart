import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/place_search/expandable_place_search.dart';
import 'package:globe_news_beta/place_search/place_search_api.dart';
import 'package:globe_news_beta/place_search/place_search_controller.dart';
import 'package:globe_news_beta/place_search/place_search_result.dart';

void main() {
  test('parses Mapbox v6 coordinates and chooses place zoom', () {
    final result = PlaceSearchResult.fromJson({
      'properties': {
        'name_preferred': 'Bengaluru',
        'feature_type': 'place',
        'coordinates': {'longitude': 77.5946, 'latitude': 12.9716},
      },
    });

    expect(result, isNotNull);
    expect(result!.name, 'Bengaluru');
    expect(result.longitude, 77.5946);
    expect(result.latitude, 12.9716);
    expect(result.preferredZoom, 7.2);
  });

  test('rejects invalid geocoding coordinates', () {
    final result = PlaceSearchResult.fromJson({
      'properties': {
        'name': 'Invalid',
        'coordinates': {'longitude': 181, 'latitude': 12},
      },
    });

    expect(result, isNull);
  });

  test('a collapsed search ignores its in-flight response', () async {
    final response = Completer<PlaceSearchResult?>();
    final api = _SearchClient(response.future);
    final controller = PlaceSearchController(api: api);
    addTearDown(controller.dispose);

    controller.toggle();
    final request = controller.submit('Bengaluru');
    controller.collapse();
    response.complete(
      const PlaceSearchResult(
        name: 'Bengaluru',
        longitude: 77.5946,
        latitude: 12.9716,
        featureType: 'place',
      ),
    );

    expect(await request, isNull);
    expect(controller.expanded, isFalse);
    expect(controller.message, isNull);
  });

  testWidgets('search icon expands into a focused text field', (tester) async {
    final controller = PlaceSearchController(
      api: _SearchClient(Future.value(null)),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ExpandablePlaceSearch(
              controller: controller,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('open-place-search')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-place-search')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('place-search-field')), findsOneWidget);
    expect(find.text('Search a place'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });
}

class _SearchClient implements PlaceSearchClient {
  _SearchClient(this.response);

  final Future<PlaceSearchResult?> response;

  @override
  Future<PlaceSearchResult?> search(String query) => response;

  @override
  void dispose() {}
}
