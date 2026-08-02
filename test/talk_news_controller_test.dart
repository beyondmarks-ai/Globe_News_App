import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/talk_news/microphone_permission.dart';
import 'package:globe_news_beta/talk_news/realtime_news_transport.dart';
import 'package:globe_news_beta/talk_news/talk_news_api.dart';
import 'package:globe_news_beta/talk_news/talk_news_controller.dart';
import 'package:globe_news_beta/talk_news/talk_news_preferences.dart';
import 'package:globe_news_beta/talk_news/talk_news_session.dart';
import 'package:globe_news_beta/timeline/timeline_news_item.dart';

void main() {
  test('connects, tracks speech states, transcripts, mute and text', () async {
    final transport = _FakeTransport();
    final controller = TalkNewsController(
      item: _item,
      api: _FakeApi(),
      transportFactory: () => transport,
      permissionGate: _PermissionGate(),
    );
    addTearDown(controller.dispose);

    await controller.start();
    expect(controller.status, TalkNewsStatus.ready);

    transport.emit(
      const RealtimeNewsEvent(RealtimeNewsEventType.userSpeechStarted),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, TalkNewsStatus.listening);

    transport.emit(
      const RealtimeNewsEvent.audioLevel(
        RealtimeNewsEventType.userAudioLevel,
        0.72,
      ),
    );
    transport.emit(
      const RealtimeNewsEvent.audioLevel(
        RealtimeNewsEventType.assistantAudioLevel,
        1.4,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.userAudioLevel, 0.72);
    expect(controller.assistantAudioLevel, 1);

    transport.emit(
      const RealtimeNewsEvent(
        RealtimeNewsEventType.assistantTranscriptDelta,
        'Bidar ',
      ),
    );
    transport.emit(
      const RealtimeNewsEvent(
        RealtimeNewsEventType.assistantTranscriptDone,
        'Bidar news answer',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.messages.last.text, 'Bidar news answer');

    await controller.toggleMute();
    expect(controller.muted, isTrue);
    expect(transport.muted, isTrue);

    await controller.sendText('Why?');
    expect(transport.sentText, 'Why?');
    expect(controller.messages.last.role, TalkMessageRole.user);

    await controller.selectLanguage(TalkNewsLanguage.kannada);
    expect(controller.language, TalkNewsLanguage.kannada);
    expect(transport.stopped, isTrue);
  });

  test('older transport events cannot update an ended controller', () async {
    final transport = _FakeTransport();
    final controller = TalkNewsController(
      item: _item,
      api: _FakeApi(),
      transportFactory: () => transport,
      permissionGate: _PermissionGate(),
    );
    addTearDown(controller.dispose);
    await controller.start();
    await controller.end();
    transport.emit(
      const RealtimeNewsEvent(
        RealtimeNewsEventType.assistantTranscriptDone,
        'stale answer',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, TalkNewsStatus.ended);
    expect(controller.messages, isEmpty);
  });

  test(
    'does not create a session when microphone permission is denied',
    () async {
      final api = _FakeApi();
      final controller = TalkNewsController(
        item: _item,
        api: api,
        transportFactory: _FakeTransport.new,
        permissionGate: _PermissionGate(MicrophonePermissionResult.denied),
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.status, TalkNewsStatus.error);
      expect(controller.errorMessage, contains('Microphone access is needed'));
      expect(api.calls, 0);
    },
  );
}

class _FakeApi implements TalkNewsSessionClient {
  int calls = 0;

  @override
  Future<TalkNewsSession> createSession({
    required TimelineNewsItem item,
    required String title,
    required TalkNewsLanguage language,
    required TalkNewsVoice voice,
  }) async {
    calls++;
    return TalkNewsSession(
      token: 'ephemeral',
      webrtcUri: Uri.parse(
        'https://example.openai.azure.com/openai/v1/realtime/calls',
      ),
    );
  }

  @override
  void dispose() {}
}

class _PermissionGate implements MicrophonePermissionGate {
  _PermissionGate([this.result = MicrophonePermissionResult.granted]);

  final MicrophonePermissionResult result;

  @override
  Future<MicrophonePermissionResult> request() async => result;

  @override
  Future<bool> openSettings() async => true;
}

class _FakeTransport implements RealtimeNewsTransport {
  final StreamController<RealtimeNewsEvent> _events =
      StreamController<RealtimeNewsEvent>.broadcast();
  bool muted = false;
  String? sentText;
  bool stopped = false;

  void emit(RealtimeNewsEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Stream<RealtimeNewsEvent> get events => _events.stream;

  @override
  Future<void> connect(TalkNewsSession session) async {
    emit(const RealtimeNewsEvent(RealtimeNewsEventType.ready));
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> sendText(String text) async => sentText = text;

  @override
  Future<void> setMuted(bool value) async => muted = value;

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_events.isClosed) await _events.close();
  }
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
