import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class AppIntroOverlay extends StatefulWidget {
  const AppIntroOverlay({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<AppIntroOverlay> createState() => _AppIntroOverlayState();
}

class _AppIntroOverlayState extends State<AppIntroOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _transitionLead = Duration(milliseconds: 700);
  static const _transitionDuration = Duration(milliseconds: 720);

  late final VideoPlayerController _videoController;
  late final AnimationController _transitionController;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  Timer? _startupGuard;
  bool _initialized = false;
  bool _transitionStarted = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _videoController = VideoPlayerController.asset(
      'Intro.mp4',
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    _transitionController = AnimationController(
      vsync: this,
      duration: _transitionDuration,
    )..addStatusListener(_onTransitionStatus);
    final curve = CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeInOutCubic,
    );
    _opacity = Tween<double>(begin: 1, end: 0).animate(curve);
    _scale = Tween<double>(begin: 1, end: 1.065).animate(curve);
    _startupGuard = Timer(const Duration(seconds: 5), _startTransition);
    unawaited(_initializeAndPlay());
  }

  Future<void> _initializeAndPlay() async {
    try {
      await _videoController.initialize();
      if (!mounted) return;
      await _videoController.setLooping(false);
      await _videoController.setVolume(0);
      _videoController.addListener(_onVideoProgress);
      _startupGuard?.cancel();
      _startupGuard = Timer(
        _videoController.value.duration + const Duration(seconds: 2),
        _startTransition,
      );
      setState(() => _initialized = true);
      await _videoController.play();
    } catch (_) {
      if (mounted) _startTransition();
    }
  }

  void _onVideoProgress() {
    if (!mounted ||
        _transitionStarted ||
        !_videoController.value.isInitialized) {
      return;
    }
    final value = _videoController.value;
    final remaining = value.duration - value.position;
    if (value.isCompleted ||
        (value.position > Duration.zero && remaining <= _transitionLead)) {
      _startTransition();
    }
  }

  void _startTransition() {
    if (!mounted || _transitionStarted) return;
    _transitionStarted = true;
    _startupGuard?.cancel();
    unawaited(_transitionController.forward());
  }

  void _onTransitionStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _finished || !mounted) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized || _transitionStarted) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_videoController.play());
    } else {
      unawaited(_videoController.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _startupGuard?.cancel();
    _videoController.removeListener(_onVideoProgress);
    unawaited(_videoController.dispose());
    _transitionController
      ..removeStatusListener(_onTransitionStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ExcludeSemantics(
          child: ColoredBox(
            color: Colors.black,
            child: FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                scale: _scale,
                child: _initialized
                    ? LayoutBuilder(
                        builder: (context, constraints) => Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: _videoController.value.size.width,
                              height: _videoController.value.size.height,
                              child: VideoPlayer(_videoController),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
