import 'dart:async';

import 'package:flutter/foundation.dart';

import '../timeline/timeline_news_item.dart';
import 'microphone_permission.dart';
import 'realtime_news_transport.dart';
import 'talk_news_api.dart';
import 'talk_news_preferences.dart';

enum TalkNewsStatus {
  idle,
  requestingPermission,
  connecting,
  ready,
  listening,
  thinking,
  speaking,
  error,
  ended,
}

enum TalkMessageRole { user, assistant }

class TalkMessage {
  const TalkMessage({required this.role, required this.text});

  final TalkMessageRole role;
  final String text;
}

class TalkNewsAudioLevels {
  const TalkNewsAudioLevels({this.user = 0, this.assistant = 0});

  final double user;
  final double assistant;
}

typedef RealtimeNewsTransportFactory = RealtimeNewsTransport Function();

class TalkNewsController extends ChangeNotifier {
  TalkNewsController({
    required this.item,
    this.title = '',
    required TalkNewsSessionClient api,
    required RealtimeNewsTransportFactory transportFactory,
    MicrophonePermissionGate? permissionGate,
  }) : _api = api,
       _transportFactory = transportFactory,
       _permissionGate = permissionGate ?? PermissionHandlerMicrophoneGate();

  final TimelineNewsItem item;
  final String title;
  final TalkNewsSessionClient _api;
  final RealtimeNewsTransportFactory _transportFactory;
  final MicrophonePermissionGate _permissionGate;

  TalkNewsStatus _status = TalkNewsStatus.idle;
  RealtimeNewsTransport? _transport;
  StreamSubscription<RealtimeNewsEvent>? _eventsSubscription;
  List<TalkMessage> _messages = const [];
  String _assistantDraft = '';
  String? _errorMessage;
  bool _muted = false;
  bool _permissionNeedsSettings = false;
  double _userAudioLevel = 0;
  double _assistantAudioLevel = 0;
  final ValueNotifier<TalkNewsAudioLevels> _audioLevels = ValueNotifier(
    const TalkNewsAudioLevels(),
  );
  TalkNewsLanguage _language = TalkNewsLanguage.auto;
  TalkNewsVoice _voice = TalkNewsVoice.coral;
  bool _disposed = false;
  int _generation = 0;

  TalkNewsStatus get status => _status;
  List<TalkMessage> get messages => _messages;
  String get assistantDraft => _assistantDraft;
  String? get errorMessage => _errorMessage;
  bool get muted => _muted;
  bool get permissionNeedsSettings => _permissionNeedsSettings;
  double get userAudioLevel => _userAudioLevel;
  double get assistantAudioLevel => _assistantAudioLevel;
  ValueListenable<TalkNewsAudioLevels> get audioLevels => _audioLevels;
  TalkNewsLanguage get language => _language;
  TalkNewsVoice get voice => _voice;
  bool get isActive => switch (_status) {
    TalkNewsStatus.ready ||
    TalkNewsStatus.listening ||
    TalkNewsStatus.thinking ||
    TalkNewsStatus.speaking => true,
    _ => false,
  };

  Future<void> start() async {
    if (_disposed ||
        _status == TalkNewsStatus.requestingPermission ||
        _status == TalkNewsStatus.connecting ||
        isActive) {
      return;
    }
    final generation = ++_generation;
    _status = TalkNewsStatus.requestingPermission;
    _errorMessage = null;
    _permissionNeedsSettings = false;
    _assistantDraft = '';
    _notify();
    await _closeTransport();
    if (_disposed || generation != _generation) return;

    final permission = await _permissionGate.request();
    if (_disposed || generation != _generation) return;
    if (permission != MicrophonePermissionResult.granted) {
      _permissionNeedsSettings =
          permission == MicrophonePermissionResult.permanentlyDenied ||
          permission == MicrophonePermissionResult.restricted;
      _errorMessage = _permissionNeedsSettings
          ? 'Microphone access is disabled for this app. Enable it in Android settings.'
          : 'Microphone access is needed to talk to this news.';
      _status = TalkNewsStatus.error;
      _notify();
      return;
    }

    _status = TalkNewsStatus.connecting;
    _notify();

    final transport = _transportFactory();
    _transport = transport;
    _eventsSubscription = transport.events.listen(
      (event) => _onEvent(event, generation),
      onError: (_) => _fail(
        generation,
        'The live audio stream was interrupted. Please try again.',
      ),
    );
    try {
      final session = await _api.createSession(
        item: item,
        title: title,
        language: _language,
        voice: _voice,
      );
      if (_disposed || generation != _generation) return;
      await transport.connect(session);
      if (_disposed || generation != _generation) return;
      if (_status == TalkNewsStatus.connecting) {
        _status = TalkNewsStatus.ready;
        _notify();
      }
    } on TalkNewsApiException catch (error) {
      _fail(generation, error.message);
    } on TalkNewsTransportException catch (error) {
      _fail(generation, error.userMessage);
    } on TimeoutException {
      _fail(
        generation,
        'The voice service timed out. Check the network and try again.',
      );
    } catch (error) {
      debugPrint(
        'Talk to News connection failed: ${error.runtimeType}: $error',
      );
      _fail(generation, 'The live audio connection could not be started.');
    }
  }

  void _onEvent(RealtimeNewsEvent event, int generation) {
    if (_disposed || generation != _generation) return;
    switch (event.type) {
      case RealtimeNewsEventType.ready:
        _status = TalkNewsStatus.ready;
      case RealtimeNewsEventType.userSpeechStarted:
        _assistantDraft = '';
        _status = TalkNewsStatus.listening;
      case RealtimeNewsEventType.userSpeechStopped:
        _status = TalkNewsStatus.thinking;
      case RealtimeNewsEventType.assistantSpeechStarted:
        _status = TalkNewsStatus.speaking;
      case RealtimeNewsEventType.assistantSpeechStopped:
        _commitAssistantDraft();
        _status = TalkNewsStatus.ready;
      case RealtimeNewsEventType.userTranscript:
        _appendMessage(TalkMessageRole.user, event.text);
      case RealtimeNewsEventType.assistantTranscriptDelta:
        _assistantDraft += event.text;
      case RealtimeNewsEventType.assistantTranscriptDone:
        if (event.text.trim().isNotEmpty) _assistantDraft = event.text.trim();
        _commitAssistantDraft();
      case RealtimeNewsEventType.userAudioLevel:
        _userAudioLevel = event.level.clamp(0.0, 1.0);
        _audioLevels.value = TalkNewsAudioLevels(
          user: _userAudioLevel,
          assistant: _assistantAudioLevel,
        );
        return;
      case RealtimeNewsEventType.assistantAudioLevel:
        _assistantAudioLevel = event.level.clamp(0.0, 1.0);
        _audioLevels.value = TalkNewsAudioLevels(
          user: _userAudioLevel,
          assistant: _assistantAudioLevel,
        );
        return;
      case RealtimeNewsEventType.error:
        _errorMessage = event.text.isEmpty
            ? 'The live conversation was interrupted.'
            : event.text;
        _status = TalkNewsStatus.error;
    }
    _notify();
  }

  void _commitAssistantDraft() {
    final text = _assistantDraft.trim();
    _assistantDraft = '';
    _appendMessage(TalkMessageRole.assistant, text);
  }

  void _appendMessage(TalkMessageRole role, String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    if (_messages.isNotEmpty &&
        _messages.last.role == role &&
        _messages.last.text == text) {
      return;
    }
    _messages = List.unmodifiable([
      ..._messages,
      TalkMessage(role: role, text: text),
    ]);
  }

  void _fail(int generation, String message) {
    if (_disposed || generation != _generation) return;
    _status = TalkNewsStatus.error;
    _errorMessage = message;
    _notify();
    unawaited(_closeTransport());
  }

  Future<void> toggleMute() async {
    if (_disposed || !isActive) return;
    final next = !_muted;
    try {
      await _transport?.setMuted(next);
      if (_disposed) return;
      _muted = next;
      _notify();
    } catch (_) {
      if (!_disposed) {
        _errorMessage = 'Microphone control is unavailable.';
        _notify();
      }
    }
  }

  Future<void> openPermissionSettings() => _permissionGate.openSettings();

  Future<void> selectLanguage(TalkNewsLanguage language) async {
    if (_disposed || identical(language, _language)) return;
    final restart = isActive || _status == TalkNewsStatus.connecting;
    _language = language;
    _notify();
    if (restart) {
      await end();
      await start();
    }
  }

  Future<void> selectVoice(TalkNewsVoice voice) async {
    if (_disposed || identical(voice, _voice)) return;
    final restart = isActive || _status == TalkNewsStatus.connecting;
    _voice = voice;
    _notify();
    if (restart) {
      await end();
      await start();
    }
  }

  Future<void> sendText(String value) async {
    final text = value.trim();
    if (_disposed || !isActive || text.isEmpty) return;
    _appendMessage(TalkMessageRole.user, text);
    _status = TalkNewsStatus.thinking;
    _notify();
    try {
      await _transport?.sendText(text);
    } catch (_) {
      if (!_disposed) {
        _errorMessage = 'Your message could not be sent.';
        _status = TalkNewsStatus.error;
        _notify();
      }
    }
  }

  Future<void> end() async {
    if (_disposed) return;
    _generation++;
    await _closeTransport();
    if (_disposed) return;
    _muted = false;
    _userAudioLevel = 0;
    _assistantAudioLevel = 0;
    _audioLevels.value = const TalkNewsAudioLevels();
    _assistantDraft = '';
    _status = TalkNewsStatus.ended;
    _notify();
  }

  Future<void> retry() => start();

  Future<void> _closeTransport() async {
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    final transport = _transport;
    _transport = null;
    if (transport != null) await transport.stop();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    unawaited(_closeTransport());
    _api.dispose();
    _audioLevels.dispose();
    super.dispose();
  }
}
