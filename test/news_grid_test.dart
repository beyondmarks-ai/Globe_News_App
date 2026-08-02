import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/news_grid/news_grid_view.dart';
import 'package:globe_news_beta/news_grid/news_view_mode.dart';
import 'package:globe_news_beta/news_grid/news_view_toggle.dart';
import 'package:globe_news_beta/timeline/timeline_news_item.dart';

void main() {
  testWidgets('toggle switches between globe and news grid', (tester) async {
    var selected = NewsViewMode.globe;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Center(
              child: NewsViewToggle(
                selected: selected,
                onSelected: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      ),
    );

    expect(selected, NewsViewMode.globe);
    await tester.tap(find.byKey(const Key('grid-view-option')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(selected, NewsViewMode.grid);
  });

  testWidgets('grid displays every supplied story and opens tapped card', (
    tester,
  ) async {
    TimelineNewsItem? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: NewsGridView(
            items: _items,
            displayDate: '02 Aug',
            displayTime: '10:30',
            isLoading: false,
            onRefresh: () async {},
            onItemSelected: (item) => selected = item,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('news-card-one')), findsOneWidget);
    expect(find.byKey(const Key('news-card-two')), findsOneWidget);
    expect(find.byKey(const Key('news-card-three')), findsOneWidget);
    expect(find.text('3 stories'), findsOneWidget);
    expect(find.text('Bidar civic update'), findsOneWidget);

    final first = tester.getRect(find.byKey(const Key('news-card-one')));
    final second = tester.getRect(find.byKey(const Key('news-card-two')));
    expect(first.width, greaterThan(280));
    expect(second.left, first.left);
    expect(second.top, greaterThan(first.bottom));

    await tester.tap(find.byKey(const Key('news-card-two')));
    expect(selected?.id, 'two');
  });

  testWidgets('grid has no overflow on a 320 pixel phone', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: NewsGridView(
            items: _items,
            displayDate: '02 Aug',
            displayTime: '10:30',
            isLoading: false,
            onRefresh: () async {},
            onItemSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('news-grid-view')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _items = [
  TimelineNewsItem(
    id: 'one',
    place: 'Bidar',
    country: 'India',
    lat: 17.91,
    lon: 77.51,
    tone: 0,
    color: 'yellow',
    url: 'https://example.com/one',
    source: 'Vijaya Karnataka',
    hasEmbedding: true,
    aiReady: true,
    pulseStrength: 1,
    headline: 'Bidar civic update',
  ),
  TimelineNewsItem(
    id: 'two',
    place: 'Bengaluru',
    country: 'India',
    lat: 12.97,
    lon: 77.59,
    tone: 2,
    color: 'green',
    url: 'https://example.com/two',
    source: 'News Source',
    hasEmbedding: false,
    aiReady: false,
    pulseStrength: 1,
  ),
  TimelineNewsItem(
    id: 'three',
    place: 'London',
    country: 'United Kingdom',
    lat: 51.5,
    lon: -0.12,
    tone: -2,
    color: 'red',
    url: 'https://example.com/three',
    source: 'World News',
    hasEmbedding: false,
    aiReady: false,
    pulseStrength: 1,
  ),
];
