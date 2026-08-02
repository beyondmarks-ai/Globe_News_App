import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/talk_news/microphone_permission.dart';
import 'package:globe_news_beta/talk_news/realtime_news_transport.dart';
import 'package:globe_news_beta/talk_news/talk_news_api.dart';
import 'package:globe_news_beta/talk_news/talk_news_controller.dart';
import 'package:globe_news_beta/talk_news/talk_news_preferences.dart';
import 'package:globe_news_beta/talk_news/talk_news_session.dart';
import 'package:globe_news_beta/talk_news/talk_news_sheet.dart';
import 'package:globe_news_beta/timeline/timeline_news_item.dart';

void main() {
  testWidgets('renders professional voice UI and sends a suggested question', (
    tester,
  ) async {
    final transport = _WidgetTransport();
    final controller = TalkNewsController(
      item: _item,
      api: _WidgetApi(),
      transportFactory: () => transport,
      permissionGate: _WidgetPermissionGate(),
    );
    addTearDown(controller.dispose);
    await controller.start();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: TalkNewsSheet(
            controller: controller,
            item: _item,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Talk to this news'), findsOneWidget);
    expect(find.byKey(const Key('talk-audio-visualizer')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('talk-voice-stage')),
        matching: find.byType(Container),
      ),
      findsNothing,
    );
    expect(find.text('Ask anything about this story'), findsOneWidget);
    expect(find.byKey(const Key('talk-mute-button')), findsOneWidget);
    expect(find.byKey(const Key('talk-end-button')), findsOneWidget);
    expect(find.byKey(const Key('talk-language-selector')), findsOneWidget);
    expect(find.byKey(const Key('talk-voice-selector')), findsOneWidget);

    transport.emit(
      const RealtimeNewsEvent(RealtimeNewsEventType.userSpeechStarted),
    );
    await tester.pump();
    var visualizerLabel = tester.widget<Text>(
      find.byKey(const Key('talk-visualizer-label')),
    );
    expect(visualizerLabel.data, 'YOU');
    expect(visualizerLabel.style?.color, const Color(0xFF22D3EE));

    transport.emit(
      const RealtimeNewsEvent(RealtimeNewsEventType.assistantSpeechStarted),
    );
    await tester.pump();
    visualizerLabel = tester.widget<Text>(
      find.byKey(const Key('talk-visualizer-label')),
    );
    expect(visualizerLabel.data, 'AI');
    expect(visualizerLabel.style?.color, const Color(0xFFF0ABFC));

    await tester.ensureVisible(find.text('What happened?'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('What happened?'));
    await tester.pump();
    expect(transport.sentText, 'What happened?');
    expect(find.text('What happened?'), findsOneWidget);
  });

  testWidgets('shows a friendly retry state without raw errors', (
    tester,
  ) async {
    final controller = TalkNewsController(
      item: _item,
      api: _FailingApi(),
      transportFactory: _WidgetTransport.new,
      permissionGate: _WidgetPermissionGate(),
    );
    addTearDown(controller.dispose);
    await controller.start();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: TalkNewsSheet(
            controller: controller,
            item: _item,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('talk-news-error')), findsOneWidget);
    expect(find.byKey(const Key('talk-retry-button')), findsOneWidget);
    expect(find.textContaining('stack trace'), findsNothing);
  });

  testWidgets('professional call dock fits a narrow phone viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TalkNewsController(
      item: _item,
      api: _WidgetApi(),
      transportFactory: _WidgetTransport.new,
      permissionGate: _WidgetPermissionGate(),
    );
    addTearDown(controller.dispose);
    await controller.start();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: TalkNewsSheet(
            controller: controller,
            item: _item,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('talk-voice-stage')), findsOneWidget);
    expect(find.byKey(const Key('talk-audio-visualizer')), findsOneWidget);
    expect(find.byKey(const Key('talk-mute-button')), findsOneWidget);
    expect(find.byKey(const Key('talk-end-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _item = TimelineNewsItem(
  id: 'bidar-vk-123',
  place: 'Bidar',
  country: 'India',
  lat: 17.91,
  lon: 77.51,
  tone: 0,
  color: 'yellow',
  url: 'https://example.com/news',
  source: 'Vijaya Karnataka',
  hasEmbedding: true,
  aiReady: true,
  pulseStrength: 1,
);

class _WidgetApi implements TalkNewsSessionClient {
  @override
  Future<TalkNewsSession> createSession({
    required TimelineNewsItem item,
    required String title,
    required TalkNewsLanguage language,
    required TalkNewsVoice voice,
  }) async => TalkNewsSession(
    token: 'ephemeral',
    webrtcUri: Uri.parse(
      'https://example.openai.azure.com/openai/v1/realtime/calls',
    ),
  );

  @override
  void dispose() {}
}

class _FailingApi implements TalkNewsSessionClient {
  @override
  Future<TalkNewsSession> createSession({
    required TimelineNewsItem item,
    required String title,
    required TalkNewsLanguage language,
    required TalkNewsVoice voice,
  }) async => throw Exception('secret stack trace');

  @override
  void dispose() {}
}

class _WidgetTransport implements RealtimeNewsTransport {
  final StreamController<RealtimeNewsEvent> _events =
      StreamController<RealtimeNewsEvent>.broadcast();
  String? sentText;

  void emit(RealtimeNewsEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Stream<RealtimeNewsEvent> get events => _events.stream;

  @override
  Future<void> connect(TalkNewsSession session) async {
    _events.add(const RealtimeNewsEvent(RealtimeNewsEventType.ready));
  }

  @override
  Future<void> sendText(String text) async => sentText = text;

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> stop() async {
    if (!_events.isClosed) await _events.close();
  }
}

class _WidgetPermissionGate implements MicrophonePermissionGate {
  @override
  Future<MicrophonePermissionResult> request() async =>
      MicrophonePermissionResult.granted;

  @override
  Future<bool> openSettings() async => true;
}
