import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'talk_news_controller.dart';

class TalkNewsVisualizer extends StatefulWidget {
  const TalkNewsVisualizer({
    super.key,
    required this.status,
    required this.muted,
    required this.userLevel,
    required this.assistantLevel,
  });

  final TalkNewsStatus status;
  final bool muted;
  final double userLevel;
  final double assistantLevel;

  @override
  State<TalkNewsVisualizer> createState() => _TalkNewsVisualizerState();
}

class _TalkNewsVisualizerState extends State<TalkNewsVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  double _smoothUserLevel = 0;
  double _smoothAssistantLevel = 0;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _presentationFor(widget.status, widget.muted);
    return Semantics(
      liveRegion: true,
      label: presentation.semantics,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: const Key('talk-audio-visualizer'),
            width: double.infinity,
            height: 76,
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, _) {
                _smoothUserLevel = _approach(
                  _smoothUserLevel,
                  widget.muted ? 0 : widget.userLevel,
                );
                _smoothAssistantLevel = _approach(
                  _smoothAssistantLevel,
                  widget.assistantLevel,
                );
                return CustomPaint(
                  painter: _SoundWavePainter(
                    phase: _animation.value,
                    status: widget.status,
                    userLevel: _smoothUserLevel,
                    assistantLevel: _smoothAssistantLevel,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(presentation.icon, size: 14, color: presentation.color),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  presentation.label,
                  key: const Key('talk-visualizer-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: presentation.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.55,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  presentation.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF95A7C0),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _approach(double current, double target) {
    final normalized = target.clamp(0.0, 1.0);
    final speed = normalized > current ? 0.42 : 0.13;
    return current + (normalized - current) * speed;
  }
}

class _SoundWavePainter extends CustomPainter {
  const _SoundWavePainter({
    required this.phase,
    required this.status,
    required this.userLevel,
    required this.assistantLevel,
  });

  final double phase;
  final TalkNewsStatus status;
  final double userLevel;
  final double assistantLevel;

  static const _userColors = [Color(0xFF22D3EE), Color(0xFF3B82F6)];
  static const _assistantColors = [Color(0xFF8B5CF6), Color(0xFFF472B6)];
  static const _neutralColors = [Color(0xFF38BDF8), Color(0xFFA78BFA)];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const barWidth = 3.2;
    const gap = 3.4;
    final barCount = math.max(17, (size.width / (barWidth + gap)).floor());
    final usedWidth = barCount * barWidth + (barCount - 1) * gap;
    final startX = (size.width - usedWidth) / 2;
    final centerY = size.height / 2;
    final activeLevel = switch (status) {
      TalkNewsStatus.listening => userLevel,
      TalkNewsStatus.speaking => assistantLevel,
      _ => 0.0,
    };
    final sensitiveLevel = math.pow(activeLevel.clamp(0.0, 1.0), 0.48);
    final activity = switch (status) {
      TalkNewsStatus.listening ||
      TalkNewsStatus.speaking => 0.22 + sensitiveLevel * 0.78,
      TalkNewsStatus.thinking || TalkNewsStatus.connecting => 0.16,
      TalkNewsStatus.error || TalkNewsStatus.ended => 0.035,
      _ => 0.08,
    };
    final colors = switch (status) {
      TalkNewsStatus.listening => _userColors,
      TalkNewsStatus.speaking || TalkNewsStatus.thinking => _assistantColors,
      _ => _neutralColors,
    };
    final shader = LinearGradient(
      colors: colors,
    ).createShader(Rect.fromLTWH(startX, 0, usedWidth, size.height));
    final paint = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill;
    final inactivePaint = Paint()..color = const Color(0xFF607795);

    for (var index = 0; index < barCount; index++) {
      final normalized = barCount == 1 ? 0.0 : index / (barCount - 1);
      final distance = (normalized - 0.5).abs() * 2;
      final envelope = math.pow(1 - distance * 0.64, 1.5).toDouble();
      final primary = (math.sin(phase * math.pi * 2.6 + index * 0.72) + 1) / 2;
      final detail = (math.sin(phase * math.pi * 4.1 - index * 1.13) + 1) / 2;
      final motion = primary * 0.66 + detail * 0.34;
      final height = 3.5 + envelope * activity * (15 + motion * 43);
      final x = startX + index * (barWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, centerY),
          width: barWidth,
          height: height.clamp(3.5, size.height - 4),
        ),
        const Radius.circular(4),
      );
      if (activity <= 0.04) {
        inactivePaint.color = const Color(
          0xFF607795,
        ).withValues(alpha: status == TalkNewsStatus.ended ? 0.2 : 0.38);
        canvas.drawRRect(rect, inactivePaint);
      } else {
        paint.color = Colors.white.withValues(alpha: 0.9);
        canvas.drawRRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SoundWavePainter oldDelegate) =>
      phase != oldDelegate.phase ||
      status != oldDelegate.status ||
      userLevel != oldDelegate.userLevel ||
      assistantLevel != oldDelegate.assistantLevel;
}

class _VisualizerPresentation {
  const _VisualizerPresentation({
    required this.label,
    required this.caption,
    required this.semantics,
    required this.icon,
    required this.color,
  });

  final String label;
  final String caption;
  final String semantics;
  final IconData icon;
  final Color color;
}

_VisualizerPresentation _presentationFor(TalkNewsStatus status, bool muted) {
  if (muted &&
      status != TalkNewsStatus.speaking &&
      status != TalkNewsStatus.thinking) {
    return const _VisualizerPresentation(
      label: 'MIC MUTED',
      caption: 'Tap the microphone to speak',
      semantics: 'Your microphone is muted',
      icon: Icons.mic_off_rounded,
      color: Color(0xFFFB7185),
    );
  }
  return switch (status) {
    TalkNewsStatus.listening => const _VisualizerPresentation(
      label: 'YOU',
      caption: 'Listening',
      semantics: 'Listening to you',
      icon: Icons.mic_rounded,
      color: Color(0xFF22D3EE),
    ),
    TalkNewsStatus.speaking => const _VisualizerPresentation(
      label: 'AI',
      caption: 'Answering — you can interrupt',
      semantics: 'AI is speaking',
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFFF0ABFC),
    ),
    TalkNewsStatus.thinking => const _VisualizerPresentation(
      label: 'AI',
      caption: 'Understanding the story',
      semantics: 'AI is thinking',
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFFA78BFA),
    ),
    TalkNewsStatus.connecting ||
    TalkNewsStatus.requestingPermission => const _VisualizerPresentation(
      label: 'CONNECTING',
      caption: 'Preparing secure live audio',
      semantics: 'Connecting live audio',
      icon: Icons.graphic_eq_rounded,
      color: Color(0xFF60A5FA),
    ),
    TalkNewsStatus.error => const _VisualizerPresentation(
      label: 'OFFLINE',
      caption: 'Live audio needs attention',
      semantics: 'Live audio has a connection problem',
      icon: Icons.warning_amber_rounded,
      color: Color(0xFFFB7185),
    ),
    TalkNewsStatus.ended => const _VisualizerPresentation(
      label: 'ENDED',
      caption: 'Conversation complete',
      semantics: 'Conversation ended',
      icon: Icons.stop_circle_outlined,
      color: Color(0xFF94A3B8),
    ),
    _ => const _VisualizerPresentation(
      label: 'LIVE',
      caption: 'Ask anything about this story',
      semantics: 'Live audio ready. Ask anything about this story',
      icon: Icons.graphic_eq_rounded,
      color: Color(0xFF7DD3FC),
    ),
  };
}
