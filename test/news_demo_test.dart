import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:globe_news_beta/news_demo/news_demo_api.dart';
import 'package:globe_news_beta/news_demo/news_demo_screen.dart';

class FakeDemo implements NewsDemoClient {
  FakeDemo({this.story = false});
  final bool story;
  final calls = <List<String?>>[];
  String? error;
  @override
  Future<Map<String, dynamic>> status() async => {
    'active': true,
    'remaining': 100,
    'expiresAt': '2026-10-05T12:00:00Z',
  };
  @override
  Future<Map<String, dynamic>> ask(
    String question,
    String requestId,
    String? previousId,
  ) async {
    calls.add([question, requestId, previousId]);
    if (error != null) throw NewsDemoError('Please verify your email.', error!);
    return {
      'requestId': requestId,
      'remaining': 99,
      'topic': 'Iran',
      'sections': [
        if (story)
          for (final heading in [
            'How it began',
            'How it developed',
            'The event you asked about',
            'Responses and what happened next',
            'Where things stand',
          ])
            {
              'heading': heading,
              'text': 'Evidence for $heading.',
              'sourceIds': [1],
            },
        if (!story)
          {
            'heading': 'Latest reports',
            'text': 'A supported report.',
            'sourceIds': [1],
          },
      ],
      'sources': [
        {'id': 1, 'title': 'Original report', 'url': 'https://news.test/story'},
      ],
      'notice': 'Based on search excerpts.',
    };
  }

  @override
  Future<void> sendVerification() async {}
  @override
  void dispose() {}
}

void main() {
  testWidgets(
    'renders the full five-part story without truncating its ending',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NewsDemoScreen(apiBaseUrl: '', client: FakeDemo(story: true)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('demo-question')),
        'Why did the protest happen?',
      );
      await tester.ensureVisible(find.byKey(const Key('demo-submit')));
      await tester.tap(find.byKey(const Key('demo-submit')));
      await tester.pumpAndSettle();
      for (final heading in [
        'How it began',
        'How it developed',
        'The event you asked about',
        'Responses and what happened next',
        'Where things stand',
      ]) {
        expect(find.text(heading), findsOneWidget);
      }
      await tester.ensureVisible(find.text('Where things stand'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'API passes bearer auth and stable request ID without retries',
    () async {
      final api = NewsDemoApi(
        baseUrl: 'https://app.test/',
        tokenProvider: () async => 'id-token',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer id-token');
          expect(jsonDecode(request.body)['requestId'], 'a' * 32);
          return http.Response(
            jsonEncode({'requestId': 'a' * 32, 'sections': []}),
            200,
          );
        }),
      );
      await api.ask('Iran news', 'a' * 32, null);
      api.dispose();
    },
  );
  test('API preserves expiry and quota error codes', () async {
    final api = NewsDemoApi(
      baseUrl: 'https://app.test/',
      tokenProvider: () async => 'token',
      client: MockClient(
        (_) async =>
            http.Response('{"error":"Demo expired","code":"expired"}', 403),
      ),
    );
    await expectLater(
      api.ask('Iran news', 'a' * 32, null),
      throwsA(isA<NewsDemoError>().having((e) => e.code, 'code', 'expired')),
    );
    api.dispose();
  });
  test('request IDs have adequate randomness and required format', () {
    final ids = List.generate(100, (_) => NewsDemoApi.newRequestId());
    expect(ids.toSet(), hasLength(100));
    expect(ids.every((id) => RegExp(r'^[a-f0-9]{32}$').hasMatch(id)), isTrue);
  });
  testWidgets('shows sources, shared quota, and follow-up conversation', (
    tester,
  ) async {
    final api = FakeDemo();
    await tester.pumpWidget(
      MaterialApp(
        home: NewsDemoScreen(apiBaseUrl: '', client: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('across all users'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('demo-question')), 'Iran news');
    await tester.ensureVisible(find.byKey(const Key('demo-submit')));
    await tester.tap(find.byKey(const Key('demo-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('A supported report'), findsOneWidget);
    expect(find.text('Original report'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('demo-question')),
      'Why did it happen?',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(api.calls[1][2], api.calls[0][1]);
  });
  testWidgets('verification retry retains the same question ID', (
    tester,
  ) async {
    final api = FakeDemo()..error = 'verify_email';
    await tester.pumpWidget(
      MaterialApp(
        home: NewsDemoScreen(apiBaseUrl: '', client: api),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('demo-question')), 'Iran news');
    await tester.ensureVisible(find.byKey(const Key('demo-submit')));
    await tester.tap(find.byKey(const Key('demo-submit')));
    await tester.pumpAndSettle();
    api.error = null;
    await tester.ensureVisible(find.text('I verified my email — retry'));
    await tester.tap(find.text('I verified my email — retry'));
    await tester.pumpAndSettle();
    expect(api.calls[0][1], api.calls[1][1]);
  });
  testWidgets('small phone with keyboard has no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: NewsDemoScreen(apiBaseUrl: '', client: FakeDemo()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
