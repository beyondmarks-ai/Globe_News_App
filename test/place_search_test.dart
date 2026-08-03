import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:globe_news_beta/globe_top_controls.dart';
import 'package:globe_news_beta/map_basemap.dart';
import 'package:globe_news_beta/place_search/expandable_place_search.dart';
import 'package:globe_news_beta/place_search/place_search_api.dart';
import 'package:globe_news_beta/place_search/place_search_controller.dart';
import 'package:globe_news_beta/place_search/place_search_result.dart';

void main() {
  test('parses separate primary and secondary Mapbox labels', () {
    final result = PlaceSearchResult.fromJson({
      'properties': {
        'name_preferred': 'Bengaluru',
        'full_address': 'Bengaluru, Karnataka, India',
        'feature_type': 'place',
        'coordinates': {'longitude': 77.5946, 'latitude': 12.9716},
      },
    });

    expect(result, isNotNull);
    expect(result!.name, 'Bengaluru');
    expect(result.description, 'Bengaluru, Karnataka, India');
    expect(result.longitude, 77.5946);
    expect(result.latitude, 12.9716);
    expect(result.preferredZoom, 7.2);
  });

  test('permanent area search requests and parses administrative bounds', () async {
    Uri? requested;
    final api = PlaceSearchApi(
      accessToken: 'public-token',
      permanentStorage: true,
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'features': [
              {
                'properties': {
                  'name': 'Bengaluru',
                  'feature_type': 'place',
                  'coordinates': {
                    'longitude': 77.591301,
                    'latitude': 12.979101,
                  },
                  'bbox': [77.325376, 12.733355, 77.783794, 13.234974],
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(api.dispose);

    final results = await api.searchMany('Bengaluru');

    expect(requested?.queryParameters['permanent'], 'true');
    expect(results.single.boundingBox, [
      77.325376,
      12.733355,
      77.783794,
      13.234974,
    ]);
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
    final api = _SearchClient((_) => response.future);
    final controller = PlaceSearchController(api: api);
    addTearDown(controller.dispose);

    controller.toggle();
    final request = controller.submit('Bengaluru');
    controller.collapse();
    response.complete(_bengaluru);

    expect(await request, isNull);
    expect(controller.expanded, isFalse);
    expect(controller.message, isNull);
  });

  testWidgets('search icon expands into a 52-pixel-high field', (tester) async {
    final controller = _controllerWithResult(_bengaluru);
    addTearDown(controller.dispose);
    await _pumpTopControls(tester, controller: controller);

    expect(_searchSize(tester), const Size(52, 52));
    await _openSearch(tester);

    expect(_searchSize(tester).height, 52);
    expect(_searchSize(tester).width, greaterThanOrEqualTo(160));
    expect(find.text('Search a place'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('map-style controls remain visible and tappable while expanded', (
    tester,
  ) async {
    final controller = _controllerWithResult(_bengaluru);
    addTearDown(controller.dispose);
    MapBasemap? selected;
    await _pumpTopControls(
      tester,
      controller: controller,
      onBasemapSelected: (value) => selected = value,
    );

    await _openSearch(tester);
    final searchRect = tester.getRect(
      find.byKey(const Key('place-search-container')),
    );
    final basemapRect = tester.getRect(
      find.byKey(const Key('basemap-selector')),
    );

    expect(searchRect.right, lessThanOrEqualTo(basemapRect.left - 8));
    expect(find.byTooltip('Dark map'), findsOneWidget);
    expect(find.byTooltip('Satellite imagery'), findsOneWidget);
    await tester.tap(find.byTooltip('Satellite imagery'));
    await tester.pump();
    expect(selected, MapBasemap.satellite);
  });

  testWidgets('suggestions use a separate matching-width compact overlay', (
    tester,
  ) async {
    final controller = _controllerWithResult(_bengaluru);
    addTearDown(controller.dispose);
    await _pumpTopControls(tester, controller: controller);
    await _openSearch(tester);

    await tester.enterText(
      find.byKey(const Key('place-search-field')),
      'Bengaluru',
    );
    await tester.pump(const Duration(milliseconds: 430));
    await tester.pump();

    final fieldRect = tester.getRect(
      find.byKey(const Key('place-search-container')),
    );
    final overlayRect = tester.getRect(
      find.byKey(const Key('place-suggestion-overlay')),
    );
    final panelSize = tester.getSize(
      find.byKey(const Key('place-suggestion-panel')),
    );

    expect(overlayRect.width, moreOrLessEquals(fieldRect.width));
    expect(overlayRect.top, moreOrLessEquals(fieldRect.bottom + 8));
    expect(panelSize.height, lessThan(120));
    expect(
      find.descendant(
        of: find.byKey(const Key('place-suggestion-panel')),
        matching: find.text('Bengaluru'),
      ),
      findsOneWidget,
    );
    expect(find.text('Bengaluru, Karnataka, India'), findsOneWidget);
  });

  testWidgets('suggestions are not rendered for an empty response', (
    tester,
  ) async {
    final controller = _controllerWithResult(null);
    addTearDown(controller.dispose);
    await _pumpTopControls(tester, controller: controller);
    await _openSearch(tester);

    await tester.enterText(
      find.byKey(const Key('place-search-field')),
      'Missing place',
    );
    await tester.pump(const Duration(milliseconds: 430));
    await tester.pump();

    expect(find.byKey(const Key('place-suggestion-overlay')), findsNothing);
    expect(find.byKey(const Key('place-suggestion-panel')), findsNothing);
  });

  testWidgets('selecting a suggestion keeps its name and closes the overlay', (
    tester,
  ) async {
    final controller = _controllerWithResult(_bengaluru);
    addTearDown(controller.dispose);
    PlaceSearchResult? selected;
    await _pumpTopControls(
      tester,
      controller: controller,
      onPlaceSelected: (value) => selected = value,
    );
    await _openSearch(tester);
    await tester.enterText(
      find.byKey(const Key('place-search-field')),
      'Bengaluru',
    );
    await tester.pump(const Duration(milliseconds: 430));
    await tester.pump();

    await tester.tap(find.byKey(const Key('place-suggestion-0')));
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const Key('place-search-field')),
    );
    expect(selected?.name, 'Bengaluru');
    expect(field.controller?.text, 'Bengaluru');
    expect(find.byKey(const Key('place-suggestion-overlay')), findsNothing);
  });

  testWidgets('close button clears the query and collapses search', (
    tester,
  ) async {
    final controller = _controllerWithResult(_bengaluru);
    addTearDown(controller.dispose);
    await _pumpTopControls(tester, controller: controller);
    await _openSearch(tester);
    await tester.enterText(
      find.byKey(const Key('place-search-field')),
      'Bengaluru',
    );

    await tester.tap(find.byKey(const Key('close-place-search')));
    await tester.pumpAndSettle();

    expect(controller.expanded, isFalse);
    expect(_searchSize(tester), const Size(52, 52));
    final field = tester.widget<TextField>(
      find.byKey(const Key('place-search-field')),
    );
    expect(field.controller?.text, isEmpty);
    expect(find.byKey(const Key('place-suggestion-overlay')), findsNothing);
  });

  testWidgets('Android back closes suggestions before collapsing search', (
    tester,
  ) async {
    final controller = _controllerWithResult(_bengaluru);
    addTearDown(controller.dispose);
    final searchKey = GlobalKey<ExpandablePlaceSearchState>();
    await _pumpTopControls(
      tester,
      controller: controller,
      searchKey: searchKey,
      handleBack: true,
    );
    await _openSearch(tester);
    await tester.enterText(
      find.byKey(const Key('place-search-field')),
      'Bengaluru',
    );
    await tester.pump(const Duration(milliseconds: 430));
    await tester.pump();
    expect(find.byKey(const Key('place-suggestion-overlay')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('place-suggestion-overlay')), findsNothing);
    expect(controller.expanded, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.expanded, isFalse);
  });

  for (final width in [320.0, 360.0, 412.0, 800.0]) {
    testWidgets('top controls do not overflow at ${width.toInt()}px', (
      tester,
    ) async {
      final controller = _controllerWithResult(_bengaluru);
      addTearDown(controller.dispose);
      await _pumpTopControls(
        tester,
        controller: controller,
        width: width,
        textScale: width == 320 ? 1.8 : 1,
      );
      await _openSearch(tester);

      expect(tester.takeException(), isNull);
      final searchRect = tester.getRect(
        find.byKey(const Key('place-search-container')),
      );
      final basemapRect = tester.getRect(
        find.byKey(const Key('basemap-selector')),
      );
      expect(searchRect.left, greaterThanOrEqualTo(16));
      expect(searchRect.right, lessThanOrEqualTo(basemapRect.left - 8));
      expect(basemapRect.right, lessThanOrEqualTo(width - 16));
    });
  }
}

const _bengaluru = PlaceSearchResult(
  name: 'Bengaluru',
  description: 'Bengaluru, Karnataka, India',
  longitude: 77.5946,
  latitude: 12.9716,
  featureType: 'place',
);

PlaceSearchController _controllerWithResult(PlaceSearchResult? result) {
  return PlaceSearchController(api: _SearchClient((_) async => result));
}

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Open location search'));
  await tester.pumpAndSettle();
}

Size _searchSize(WidgetTester tester) {
  return tester.getSize(find.byKey(const Key('place-search-container')));
}

Future<void> _pumpTopControls(
  WidgetTester tester, {
  required PlaceSearchController controller,
  double width = 412,
  double textScale = 1,
  ValueChanged<PlaceSearchResult>? onPlaceSelected,
  ValueChanged<MapBasemap>? onBasemapSelected,
  GlobalKey<ExpandablePlaceSearchState>? searchKey,
  bool handleBack = false,
}) async {
  final controls = GlobeTopControls(
    searchKey: searchKey,
    searchController: controller,
    onPlaceSelected: onPlaceSelected ?? (_) {},
    selectedBasemap: MapBasemap.dark,
    isBasemapBusy: false,
    onBasemapSelected: onBasemapSelected ?? (_) {},
    alertsEnabled: false,
    onAlertsPressed: () {},
  );

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: handleBack
                      ? ListenableBuilder(
                          listenable: controller,
                          child: controls,
                          builder: (context, child) => PopScope<Object?>(
                            canPop: !controller.expanded,
                            onPopInvokedWithResult: (didPop, result) {
                              if (!didPop) {
                                searchKey?.currentState?.handleBack();
                              }
                            },
                            child: child!,
                          ),
                        )
                      : controls,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SearchClient implements PlaceSearchClient {
  _SearchClient(this.handler);

  final Future<PlaceSearchResult?> Function(String query) handler;

  @override
  Future<PlaceSearchResult?> search(String query) => handler(query);

  @override
  void dispose() {}
}
