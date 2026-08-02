import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import 'talk_news_session.dart';

enum RealtimeNewsEventType {
  ready,
  userSpeechStarted,
  userSpeechStopped,
  assistantSpeechStarted,
  assistantSpeechStopped,
  userTranscript,
  assistantTranscriptDelta,
  assistantTranscriptDone,
  userAudioLevel,
  assistantAudioLevel,
  error,
}

class RealtimeNewsEvent {
  const RealtimeNewsEvent(this.type, [this.text = '']) : level = 0;

  const RealtimeNewsEvent.audioLevel(this.type, this.level) : text = '';

  final RealtimeNewsEventType type;
  final String text;
  final double level;
}

abstract interface class RealtimeNewsTransport {
  Stream<RealtimeNewsEvent> get events;

  Future<void> connect(TalkNewsSession session);

  Future<void> setMuted(bool muted);

  Future<void> sendText(String text);

  Future<void> stop();
}

class TalkNewsTransportException implements Exception {
  const TalkNewsTransportException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}

class WebRtcRealtimeNewsTransport implements RealtimeNewsTransport {
  WebRtcRealtimeNewsTransport({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  final StreamController<RealtimeNewsEvent> _events =
      StreamController<RealtimeNewsEvent>.broadcast();
  RTCPeerConnection? _peer;
  RTCDataChannel? _channel;
  MediaStream? _localStream;
  MediaStreamTrack? _microphone;
  RTCVideoRenderer? _remoteAudioRenderer;
  Timer? _meterTimer;
  final Map<String, ({double energy, double duration})> _previousEnergy = {};
  bool _meterBusy = false;
  bool _stopped = false;

  @override
  Stream<RealtimeNewsEvent> get events => _events.stream;

  @override
  Future<void> connect(TalkNewsSession session) async {
    if (_stopped) throw StateError('Realtime transport is stopped');
    final renderer = RTCVideoRenderer();
    try {
      await renderer.initialize();
    } catch (_) {
      throw const TalkNewsTransportException(
        'The phone audio engine could not be started.',
      );
    }
    _remoteAudioRenderer = renderer;

    late final MediaStream stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
    } catch (_) {
      throw const TalkNewsTransportException(
        'Android could not open the microphone. Check the system microphone toggle and close other recording apps.',
      );
    }
    if (_stopped) {
      await stream.dispose();
      return;
    }
    _localStream = stream;
    final tracks = stream.getAudioTracks();
    if (tracks.isEmpty) {
      throw const TalkNewsTransportException(
        'No microphone input device is available.',
      );
    }
    _microphone = tracks.first;

    late final RTCPeerConnection peer;
    try {
      peer = await createPeerConnection({
        'iceServers': <Object>[],
        'sdpSemantics': 'unified-plan',
      });
    } catch (error, stackTrace) {
      _logStageFailure('peer creation', error, stackTrace);
      throw const TalkNewsTransportException(
        'The phone could not create a secure live-audio connection.',
      );
    }
    _peer = peer;
    peer.onTrack = (event) {
      if (event.track.kind != 'audio') return;
      event.track.enabled = true;
      if (event.streams.isNotEmpty) {
        renderer.srcObject = event.streams.first;
      }
      unawaited(_enableSpeakerphoneBestEffort());
    };
    peer.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          !_stopped) {
        _emit(
          const RealtimeNewsEvent(
            RealtimeNewsEventType.error,
            'The live audio connection was interrupted.',
          ),
        );
      }
    };
    late final RTCDataChannel channel;
    try {
      await peer.addTrack(_microphone!, stream);
      channel = await peer.createDataChannel(
        'realtime-channel',
        RTCDataChannelInit()..ordered = true,
      );
    } catch (error, stackTrace) {
      _logStageFailure('local audio setup', error, stackTrace);
      throw const TalkNewsTransportException(
        'The phone could not attach the microphone to the live conversation.',
      );
    }
    _channel = channel;
    final channelReady = Completer<void>();
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen &&
          !channelReady.isCompleted) {
        channelReady.complete();
        _emit(const RealtimeNewsEvent(RealtimeNewsEventType.ready));
      }
    };
    channel.onMessage = _handleMessage;

    late final RTCSessionDescription offer;
    try {
      offer = await peer.createOffer({'offerToReceiveAudio': true});
      await peer.setLocalDescription(offer);
    } catch (error, stackTrace) {
      _logStageFailure('local SDP', error, stackTrace);
      throw const TalkNewsTransportException(
        'The phone could not prepare the live audio connection.',
      );
    }
    final sdp = offer.sdp;
    if (sdp == null || sdp.isEmpty) {
      throw const TalkNewsTransportException(
        'The phone could not prepare the live audio connection.',
      );
    }
    late final http.Response response;
    try {
      response = await _http
          .post(
            session.webrtcUri,
            headers: {
              'Authorization': 'Bearer ${session.token}',
              'Content-Type': 'application/sdp',
            },
            body: sdp,
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      rethrow;
    } catch (error, stackTrace) {
      _logStageFailure('Azure SDP request', error, stackTrace);
      throw const TalkNewsTransportException(
        'The phone could not reach Azure Live Audio. Check the network and try again.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        'Talk to News Azure SDP failed with HTTP ${response.statusCode}.',
      );
      throw const TalkNewsTransportException(
        'Azure Live Audio could not negotiate this connection.',
      );
    }
    try {
      await peer.setRemoteDescription(
        RTCSessionDescription(response.body, 'answer'),
      );
    } catch (error, stackTrace) {
      _logStageFailure('remote SDP', error, stackTrace);
      throw const TalkNewsTransportException(
        'Azure Live Audio returned an incompatible connection response.',
      );
    }
    await _enableSpeakerphoneBestEffort();
    try {
      await channelReady.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const TalkNewsTransportException(
        'The live audio channel timed out. Check the network and try again.',
      );
    }
    _startAudioMetering();
  }

  void _startAudioMetering() {
    _meterTimer?.cancel();
    _meterTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      unawaited(_sampleAudioLevels());
    });
  }

  Future<void> _sampleAudioLevels() async {
    final peer = _peer;
    if (_stopped || peer == null || _meterBusy) return;
    _meterBusy = true;
    try {
      final reports = await peer.getStats();
      var userLevel = 0.0;
      var assistantLevel = 0.0;
      for (final report in reports) {
        final values = report.values;
        final mediaKind = (values['kind'] ?? values['mediaType'])?.toString();
        if (mediaKind != 'audio') continue;
        final level = _audioLevelFor(report.id, values);
        if (report.type == 'media-source' || report.type == 'outbound-rtp') {
          userLevel = math.max(userLevel, level);
        } else if (report.type == 'inbound-rtp') {
          assistantLevel = math.max(assistantLevel, level);
        }
      }
      _emit(
        RealtimeNewsEvent.audioLevel(
          RealtimeNewsEventType.userAudioLevel,
          userLevel,
        ),
      );
      _emit(
        RealtimeNewsEvent.audioLevel(
          RealtimeNewsEventType.assistantAudioLevel,
          assistantLevel,
        ),
      );
    } catch (_) {
      // Audio metering is an enhancement; unsupported stats must not end calls.
    } finally {
      _meterBusy = false;
    }
  }

  double _audioLevelFor(String id, Map<dynamic, dynamic> values) {
    final direct = _asDouble(values['audioLevel']);
    if (direct != null && direct.isFinite) {
      return direct.clamp(0.0, 1.0);
    }
    final energy = _asDouble(values['totalAudioEnergy']);
    final duration = _asDouble(values['totalSamplesDuration']);
    if (energy == null || duration == null) return 0;
    final previous = _previousEnergy[id];
    _previousEnergy[id] = (energy: energy, duration: duration);
    if (previous == null) return 0;
    final energyDelta = energy - previous.energy;
    final durationDelta = duration - previous.duration;
    if (energyDelta <= 0 || durationDelta <= 0) return 0;
    return math.sqrt(energyDelta / durationDelta).clamp(0.0, 1.0);
  }

  double? _asDouble(Object? value) => switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };

  void _handleMessage(RTCDataChannelMessage message) {
    if (_stopped || message.isBinary) return;
    try {
      final decoded = jsonDecode(message.text);
      if (decoded is! Map) return;
      final event = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final type = event['type']?.toString();
      switch (type) {
        case 'input_audio_buffer.speech_started':
          _emit(
            const RealtimeNewsEvent(RealtimeNewsEventType.userSpeechStarted),
          );
        case 'input_audio_buffer.speech_stopped':
          _emit(
            const RealtimeNewsEvent(RealtimeNewsEventType.userSpeechStopped),
          );
        case 'output_audio_buffer.started':
          _emit(
            const RealtimeNewsEvent(
              RealtimeNewsEventType.assistantSpeechStarted,
            ),
          );
        case 'output_audio_buffer.stopped':
          _emit(
            const RealtimeNewsEvent(
              RealtimeNewsEventType.assistantSpeechStopped,
            ),
          );
        case 'conversation.item.input_audio_transcription.completed':
        case 'conversation.item.audio_transcription.completed':
          _emit(
            RealtimeNewsEvent(
              RealtimeNewsEventType.userTranscript,
              event['transcript']?.toString() ?? '',
            ),
          );
        case 'response.output_audio_transcript.delta':
        case 'response.output_text.delta':
          _emit(
            RealtimeNewsEvent(
              RealtimeNewsEventType.assistantTranscriptDelta,
              event['delta']?.toString() ?? '',
            ),
          );
        case 'response.output_audio_transcript.done':
        case 'response.output_text.done':
          _emit(
            RealtimeNewsEvent(
              RealtimeNewsEventType.assistantTranscriptDone,
              (event['transcript'] ?? event['text'])?.toString() ?? '',
            ),
          );
        case 'error':
        case 'session.error':
          _emit(
            const RealtimeNewsEvent(
              RealtimeNewsEventType.error,
              'The voice assistant encountered a temporary problem.',
            ),
          );
      }
    } on FormatException {
      // Ignore malformed data-channel events without affecting the call.
    }
  }

  void _emit(RealtimeNewsEvent event) {
    if (!_stopped && !_events.isClosed) _events.add(event);
  }

  void _logStageFailure(String stage, Object error, StackTrace stackTrace) {
    debugPrint(
      'Talk to News $stage failed: ${error.runtimeType}: $error\n$stackTrace',
    );
  }

  Future<void> _enableSpeakerphoneBestEffort() async {
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (error) {
      // Some Android OEMs reject explicit route selection even though WebRTC
      // audio is working. Keep the conversation alive on the active route.
      debugPrint(
        'Talk to News speaker routing was unavailable: '
        '${error.runtimeType}: $error',
      );
    }
  }

  @override
  Future<void> setMuted(bool muted) async {
    final microphone = _microphone;
    if (microphone == null) return;
    microphone.enabled = !muted;
    await Helper.setMicrophoneMute(muted, microphone);
  }

  @override
  Future<void> sendText(String text) async {
    final channel = _channel;
    final trimmed = text.trim();
    if (channel?.state != RTCDataChannelState.RTCDataChannelOpen ||
        trimmed.isEmpty) {
      return;
    }
    await channel!.send(
      RTCDataChannelMessage(
        jsonEncode({
          'type': 'conversation.item.create',
          'item': {
            'type': 'message',
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': trimmed},
            ],
          },
        }),
      ),
    );
    await channel.send(
      RTCDataChannelMessage(jsonEncode({'type': 'response.create'})),
    );
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _meterTimer?.cancel();
    _meterTimer = null;
    _previousEnergy.clear();
    final microphone = _microphone;
    _microphone = null;
    if (microphone != null) await microphone.stop();
    final stream = _localStream;
    _localStream = null;
    if (stream != null) await stream.dispose();
    final channel = _channel;
    _channel = null;
    if (channel != null) await channel.close();
    final peer = _peer;
    _peer = null;
    if (peer != null) await peer.close();
    final renderer = _remoteAudioRenderer;
    _remoteAudioRenderer = null;
    if (renderer != null) {
      renderer.srcObject = null;
      await renderer.dispose();
    }
    _http.close();
    await _events.close();
  }
}
