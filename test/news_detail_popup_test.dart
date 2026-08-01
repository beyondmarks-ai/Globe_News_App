import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/article/article_details.dart';
import 'package:globe_news_beta/article/article_details_api.dart';
import 'package:globe_news_beta/article/article_language.dart';
import 'package:globe_news_beta/article/article_summary_cache.dart';
import 'package:globe_news_beta/article/article_summary_controller.dart';
import 'package:globe_news_beta/article/news_detail_popup.dart';
import 'package:globe_news_beta/timeline/timeline_news_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows timeline information and loading state immediately', (
    tester,
  ) async {
    final completer = Completer<ArticleDetails>();
    final controller = _controller(_CompleterClient(completer));
    addTearDown(controller.dispose);
    unawaited(controller.load());

    await _pumpPopup(tester, controller);

    expect(find.text('Bidar, India'), findsWidgets);
    expect(find.text('Example News'), findsOneWidget);
    expect(find.text('-3.2'), findsOneWidget);
    expect(find.byKey(const Key('article-summary-loading')), findsOneWidget);
    expect(
      find.text('Reading and summarizing the original article…'),
      findsOneWidget,
    );
  });

  testWidgets('renders a successful summary and image fallback', (
    tester,
  ) async {
    final controller = _controller(
      _SuccessClient(_details(title: 'AI headline', imageUrl: null)),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await _pumpPopup(tester, controller);

    expect(find.text('AI headline'), findsOneWidget);
    expect(find.text('What happened'), findsWidgets);
    expect(find.text('A concise factual summary.'), findsOneWidget);
    expect(find.byKey(const Key('article-image-fallback')), findsOneWidget);

    final sectionWidths = [
      'summary-what-happened',
      'summary-when',
      'summary-where',
      'summary-why',
      'summary-how',
    ].map((key) => tester.getSize(find.byKey(Key(key))).width).toSet();
    expect(sectionWidths, hasLength(1));
  });

  testWidgets('keeps popup open on error and retries', (tester) async {
    final api = _RetryClient();
    final controller = _controller(api);
    addTearDown(controller.dispose);
    await controller.load();
    await _pumpPopup(tester, controller);

    expect(find.text('This article could not be summarized.'), findsOneWidget);
    expect(find.byKey(const Key('news-detail-popup')), findsOneWidget);

    await tester.tap(find.byKey(const Key('article-retry-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Retry success'), findsOneWidget);
  });

  testWidgets('opens only the validated original source URL', (tester) async {
    Uri? launched;
    final controller = _controller(_SuccessClient(_details()));
    addTearDown(controller.dispose);
    await controller.load();
    await _pumpPopup(
      tester,
      controller,
      launcher: (uri) async {
        launched = uri;
        return true;
      },
    );

    await tester.ensureVisible(find.byKey(const Key('open-original-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-original-button')));
    await tester.pump();

    expect(launched, Uri.parse('https://example.com/story'));
  });

  testWidgets('switches language and uses RTL for Urdu', (tester) async {
    final controller = _controller(_LanguageClient());
    addTearDown(controller.dispose);
    await controller.load();
    await _pumpPopup(tester, controller);

    await tester.tap(find.byKey(const Key('article-language-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ArticleLanguage.urdu.label).last);
    await tester.pumpAndSettle();

    expect(controller.language, ArticleLanguage.urdu);
    expect(find.text('ur-PK summary'), findsOneWidget);
    final directionality = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.byKey(const Key('news-detail-popup')),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  });

  testWidgets('close button dismisses the popup content', (tester) async {
    var closed = false;
    final controller = _controller(_SuccessClient(_details()));
    addTearDown(controller.dispose);
    await controller.load();
    await _pumpPopup(tester, controller, onClose: () => closed = true);

    await tester.tap(find.byKey(const Key('popup-close-button')));
    await tester.pump();

    expect(closed, isTrue);
  });
}

Future<void> _pumpPopup(
  WidgetTester tester,
  ArticleSummaryController controller, {
  ArticleLauncher? launcher,
  VoidCallback? onClose,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: NewsDetailPopup(
          controller: controller,
          onClose: onClose ?? () {},
          launcher: launcher,
        ),
      ),
    ),
  );
  await tester.pump();
}

ArticleSummaryController _controller(ArticleDetailsClient api) =>
    ArticleSummaryController(
      item: _item,
      api: api,
      cache: ArticleSummaryCache(),
    );

const _item = TimelineNewsItem(
  id: 'story-1',
  place: 'Bidar',
  country: 'India',
  lat: 17.91,
  lon: 77.51,
  tone: -3.2,
  color: 'red',
  url: 'https://example.com/story',
  source: 'Example News',
  hasEmbedding: true,
  aiReady: true,
  pulseStrength: 1,
);

ArticleDetails _details({String title = 'Headline', String? imageUrl}) =>
    ArticleDetails(
      title: title,
      emoji: '📰',
      whatHappened: 'A concise factual summary.',
      when: 'Today',
      where: 'Bidar',
      why: 'A stated reason',
      how: 'A stated method',
      imageUrl: imageUrl,
    );

class _CompleterClient implements ArticleDetailsClient {
  _CompleterClient(this.completer);
  final Completer<ArticleDetails> completer;

  @override
  Future<ArticleDetails> fetch({
    required String articleUrl,
    required ArticleLanguage language,
  }) => completer.future;

  @override
  void cancel() {}
  @override
  void dispose() {}
}

class _SuccessClient implements ArticleDetailsClient {
  _SuccessClient(this.details);
  final ArticleDetails details;

  @override
  Future<ArticleDetails> fetch({
    required String articleUrl,
    required ArticleLanguage language,
  }) async => details;

  @override
  void cancel() {}
  @override
  void dispose() {}
}

class _RetryClient implements ArticleDetailsClient {
  int attempts = 0;

  @override
  Future<ArticleDetails> fetch({
    required String articleUrl,
    required ArticleLanguage language,
  }) async {
    attempts++;
    if (attempts == 1) throw Exception('server detail must stay hidden');
    return _details(title: 'Retry success');
  }

  @override
  void cancel() {}
  @override
  void dispose() {}
}

class _LanguageClient implements ArticleDetailsClient {
  @override
  Future<ArticleDetails> fetch({
    required String articleUrl,
    required ArticleLanguage language,
  }) async => _details(title: '${language.code} summary');

  @override
  void cancel() {}
  @override
  void dispose() {}
}
