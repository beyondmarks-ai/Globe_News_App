import 'dart:async';

import 'package:flutter/material.dart';

import '../timeline/timeline_news_item.dart';
import 'realtime_news_transport.dart';
import 'talk_news_api.dart';
import 'talk_news_controller.dart';
import 'talk_news_preferences.dart';
import 'talk_news_visualizer.dart';

bool supportsTalkToNews(TimelineNewsItem item) => item.id.trim().isNotEmpty;

Future<void> showTalkNewsSheet({
  required BuildContext context,
  required TimelineNewsItem item,
  required String apiBaseUrl,
  String title = '',
}) async {
  final controller = TalkNewsController(
    item: item,
    title: title,
    api: TalkNewsApi(baseUrl: apiBaseUrl),
    transportFactory: WebRtcRealtimeNewsTransport.new,
  );
  unawaited(controller.start());
  try {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      isDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: MediaQuery.sizeOf(sheetContext).width >= 700
            ? 0.78
            : 0.94,
        child: TalkNewsSheet(
          controller: controller,
          item: item,
          onClose: () => Navigator.pop(sheetContext),
        ),
      ),
    );
  } finally {
    await controller.end();
    controller.dispose();
  }
}

class TalkNewsSheet extends StatefulWidget {
  const TalkNewsSheet({
    super.key,
    required this.controller,
    required this.item,
    required this.onClose,
  });

  final TalkNewsController controller;
  final TimelineNewsItem item;
  final VoidCallback onClose;

  @override
  State<TalkNewsSheet> createState() => _TalkNewsSheetState();
}

class _TalkNewsSheetState extends State<TalkNewsSheet>
    with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _messagesController = ScrollController();
  bool _resumeAfterBackground = false;
  bool _userBrowsingHistory = false;
  bool _showJumpToLatest = false;
  bool _autoScrolling = false;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerChanged);
    _messagesController.addListener(_onMessagesScrolled);
    _lastMessageCount = widget.controller.messages.length;
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final hasNewCompletedMessage =
        widget.controller.messages.length > _lastMessageCount;
    _lastMessageCount = widget.controller.messages.length;
    setState(() {
      if (hasNewCompletedMessage && _userBrowsingHistory) {
        _showJumpToLatest = true;
      }
    });
    if (!hasNewCompletedMessage || _userBrowsingHistory) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToLatest();
    });
  }

  void _onMessagesScrolled() {
    if (!mounted || !_messagesController.hasClients || _autoScrolling) return;
    final browsing =
        _messagesController.position.maxScrollExtent -
            _messagesController.offset >
        72;
    if (browsing == _userBrowsingHistory) return;
    setState(() {
      _userBrowsingHistory = browsing;
      if (!browsing) _showJumpToLatest = false;
    });
  }

  Future<void> _scrollToLatest() async {
    if (!_messagesController.hasClients) return;
    _autoScrolling = true;
    if (mounted) {
      setState(() {
        _userBrowsingHistory = false;
        _showJumpToLatest = false;
      });
    }
    try {
      await _messagesController.animateTo(
        _messagesController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _autoScrolling = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_resumeAfterBackground) {
        _resumeAfterBackground = false;
        unawaited(widget.controller.start());
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        widget.controller.status == TalkNewsStatus.requestingPermission) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _resumeAfterBackground =
          widget.controller.isActive ||
          widget.controller.status == TalkNewsStatus.connecting;
      unawaited(widget.controller.end());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    _messagesController.removeListener(_onMessagesScrolled);
    _textController.dispose();
    _messagesController.dispose();
    super.dispose();
  }

  void _sendText([String? suggestion]) {
    final value = suggestion ?? _textController.text;
    if (value.trim().isEmpty) return;
    _textController.clear();
    FocusScope.of(context).unfocus();
    unawaited(widget.controller.sendText(value));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Material(
      key: const Key('talk-news-sheet'),
      color: const Color(0xFF07101C),
      elevation: 30,
      shadowColor: Colors.black,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E2036), Color(0xFF07101C)],
          ),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ),
        child: Column(
          children: [
            const _SheetHandle(),
            _TalkHeader(item: widget.item, onClose: widget.onClose),
            _PreferenceSelectors(controller: controller),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _VoiceStage(controller: controller),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Stack(
                children: [
                  ListView(
                    controller: _messagesController,
                    padding: const EdgeInsets.fromLTRB(18, 2, 18, 26),
                    children: [
                      if (controller.status == TalkNewsStatus.error)
                        _ErrorPanel(
                          message:
                              controller.errorMessage ??
                              'Live conversation is unavailable.',
                          onRetry: controller.retry,
                          needsSettings: controller.permissionNeedsSettings,
                          onOpenSettings: controller.openPermissionSettings,
                        )
                      else if (controller.status == TalkNewsStatus.ended)
                        _ReconnectPanel(onReconnect: controller.start)
                      else if (controller.messages.isEmpty &&
                          controller.assistantDraft.isEmpty)
                        _Suggestions(onSelected: _sendText)
                      else
                        _Conversation(controller: controller),
                    ],
                  ),
                  if (_showJumpToLatest)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 8,
                      child: Center(
                        child: FilledButton.tonalIcon(
                          key: const Key('talk-jump-to-latest'),
                          onPressed: _scrollToLatest,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xF21B2A40),
                            foregroundColor: const Color(0xFFD8E9FF),
                            visualDensity: VisualDensity.compact,
                            side: const BorderSide(color: Color(0xFF365170)),
                            elevation: 8,
                          ),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                          ),
                          label: const Text('Jump to latest'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _ConversationControls(
              controller: controller,
              textController: _textController,
              onSend: _sendText,
              onEnd: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceSelectors extends StatelessWidget {
  const _PreferenceSelectors({required this.controller});
  final TalkNewsController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final language = _PreferenceField<TalkNewsLanguage>(
          key: const Key('talk-language-selector'),
          icon: Icons.translate_rounded,
          label: 'Reply language',
          value: controller.language,
          items: TalkNewsLanguage.values,
          itemLabel: (value) => value.label,
          onChanged: (value) {
            if (value != null) unawaited(controller.selectLanguage(value));
          },
        );
        final voice = _PreferenceField<TalkNewsVoice>(
          key: const Key('talk-voice-selector'),
          icon: Icons.record_voice_over_rounded,
          label: 'Voice',
          value: controller.voice,
          items: TalkNewsVoice.values,
          itemLabel: (value) => '${value.label} · ${value.description}',
          onChanged: (value) {
            if (value != null) unawaited(controller.selectVoice(value));
          },
        );
        if (constraints.maxWidth < 330) {
          return Column(children: [language, const SizedBox(height: 8), voice]);
        }
        return Row(
          children: [
            Expanded(child: language),
            const SizedBox(width: 10),
            Expanded(child: voice),
          ],
        );
      },
    ),
  );
}

class _PreferenceField<T> extends StatelessWidget {
  const _PreferenceField({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final T value;
  final List<T> items;
  final String Function(T value) itemLabel;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 11),
    decoration: BoxDecoration(
      color: const Color(0xB30C1727),
      border: Border.all(color: const Color(0xFF263C58)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF75C7FF)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(16),
              dropdownColor: const Color(0xFF111827),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              items: items
                  .map(
                    (item) => DropdownMenuItem<T>(
                      value: item,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Color(0xFF8296B3),
                              fontSize: 9.5,
                            ),
                          ),
                          Text(
                            itemLabel(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 10),
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );
}

class _TalkHeader extends StatelessWidget {
  const _TalkHeader({required this.item, required this.onClose});
  final TimelineNewsItem item;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF22D3EE), Color(0xFF2563EB)],
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.24),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.spatial_audio_off_rounded,
            color: Colors.white,
            size: 23,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Flexible(
                    child: Text(
                      'Talk to this news',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.25,
                      ),
                    ),
                  ),
                  if (MediaQuery.sizeOf(context).width >= 360) ...const [
                    SizedBox(width: 8),
                    _LiveBadge(),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                [
                  item.source,
                  item.place,
                  item.country,
                ].where((value) => value.trim().isNotEmpty).join('  •  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF9AAAC2), fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('talk-close-button'),
          tooltip: 'Close conversation',
          onPressed: onClose,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            foregroundColor: const Color(0xFFD7E2F3),
          ),
          icon: const Icon(Icons.close_rounded, size: 21),
        ),
      ],
    ),
  );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFF10B981).withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: const Color(0xFF34D399).withValues(alpha: 0.35),
      ),
    ),
    child: const Text(
      'LIVE',
      style: TextStyle(
        color: Color(0xFF6EE7B7),
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _VoiceStage extends StatelessWidget {
  const _VoiceStage({required this.controller});

  final TalkNewsController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller.audioLevels,
    builder: (context, levels, _) => TalkNewsVisualizer(
      key: const Key('talk-voice-stage'),
      status: controller.status,
      muted: controller.muted,
      userLevel: levels.user,
      assistantLevel: levels.assistant,
    ),
  );
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onSelected});
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const suggestions = [
      (Icons.newspaper_rounded, 'What happened?'),
      (Icons.insights_rounded, 'Why does this matter?'),
      (Icons.translate_rounded, 'ಈ ಸುದ್ದಿಯನ್ನು ಸರಳವಾಗಿ ವಿವರಿಸಿ'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 16,
              color: Color(0xFF75C7FF),
            ),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                'Start with a question',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFFB8C7DB),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...suggestions.map((suggestion) {
          final (icon, text) = suggestion;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: const Color(0x99101C2D),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () => onSelected(text),
                borderRadius: BorderRadius.circular(16),
                splashColor: const Color(0xFF38BDF8).withValues(alpha: 0.08),
                highlightColor: Colors.white.withValues(alpha: 0.03),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 54),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF263C58)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          icon,
                          size: 17,
                          color: const Color(0xFF8FD3FF),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFE5EDF8),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 17,
                        color: Color(0xFF7185A3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({required this.controller});
  final TalkNewsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...controller.messages.map(
          (message) => _MessageBubble(message: message),
        ),
        if (controller.assistantDraft.isNotEmpty)
          _MessageBubble(
            message: TalkMessage(
              role: TalkMessageRole.assistant,
              text: controller.assistantDraft,
            ),
            streaming: true,
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.streaming = false});
  final TalkMessage message;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final assistant = message.role == TalkMessageRole.assistant;
    return Align(
      alignment: assistant ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: assistant ? const Color(0xFF172033) : const Color(0xFF1D4ED8),
          border: Border.all(
            color: assistant
                ? const Color(0xFF2D4168)
                : const Color(0xFF60A5FA),
          ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(17),
            topRight: const Radius.circular(17),
            bottomLeft: Radius.circular(assistant ? 5 : 17),
            bottomRight: Radius.circular(assistant ? 17 : 5),
          ),
        ),
        child: Text(
          streaming ? '${message.text} •' : message.text,
          textDirection: _looksRtl(message.text) ? TextDirection.rtl : null,
          style: const TextStyle(height: 1.4),
        ),
      ),
    );
  }
}

bool _looksRtl(String value) => RegExp(r'[\u0600-\u06FF]').hasMatch(value);

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.onRetry,
    required this.needsSettings,
    required this.onOpenSettings,
  });
  final String message;
  final VoidCallback onRetry;
  final bool needsSettings;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('talk-news-error'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF7F1D1D).withValues(alpha: 0.22),
      border: Border.all(
        color: const Color(0xFFFB7185).withValues(alpha: 0.55),
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const Key('talk-retry-button'),
          onPressed: needsSettings ? onOpenSettings : onRetry,
          icon: Icon(
            needsSettings ? Icons.settings_rounded : Icons.refresh_rounded,
          ),
          label: Text(needsSettings ? 'Open app settings' : 'Try again'),
        ),
      ],
    ),
  );
}

class _ReconnectPanel extends StatelessWidget {
  const _ReconnectPanel({required this.onReconnect});
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('talk-news-reconnect'),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF172033),
      border: Border.all(color: const Color(0xFF2D4168)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        const Text(
          'The live audio session ended while the app was away.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFC5CEE2)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('talk-reconnect-button'),
          onPressed: onReconnect,
          icon: const Icon(Icons.call_rounded),
          label: const Text('Reconnect'),
        ),
      ],
    ),
  );
}

class _ConversationControls extends StatelessWidget {
  const _ConversationControls({
    required this.controller,
    required this.textController,
    required this.onSend,
    required this.onEnd,
  });
  final TalkNewsController controller;
  final TextEditingController textController;
  final VoidCallback onSend;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: EdgeInsets.fromLTRB(
        14,
        11,
        14,
        10 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFA07101C),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.only(left: 5, right: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1A2A),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF263C58)),
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.keyboard_rounded,
                    size: 18,
                    color: Color(0xFF7185A3),
                  ),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('talk-text-field'),
                    controller: textController,
                    enabled: controller.isActive,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    maxLines: 1,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Type a question about this story',
                      hintStyle: TextStyle(
                        color: Color(0xFF7185A3),
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 15,
                      ),
                    ),
                  ),
                ),
                IconButton.filled(
                  key: const Key('talk-send-button'),
                  tooltip: 'Send question',
                  onPressed: controller.isActive ? onSend : null,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    disabledBackgroundColor: const Color(0xFF1B2A3D),
                    minimumSize: const Size(40, 40),
                    maximumSize: const Size(40, 40),
                  ),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton.filledTonal(
                key: const Key('talk-mute-button'),
                tooltip: controller.muted
                    ? 'Unmute microphone'
                    : 'Mute microphone',
                onPressed: controller.isActive ? controller.toggleMute : null,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF142236),
                  foregroundColor: controller.muted
                      ? const Color(0xFFFB7185)
                      : const Color(0xFFB9DFFF),
                  disabledBackgroundColor: const Color(0xFF101A28),
                  minimumSize: const Size(48, 48),
                ),
                icon: Icon(
                  controller.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  size: 21,
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: controller.isActive
                                ? const Color(0xFF34D399)
                                : const Color(0xFF7185A3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          controller.isActive ? 'Live audio' : 'Audio paused',
                          style: const TextStyle(
                            color: Color(0xFFB8C7DB),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Grounded in the original article',
                      style: TextStyle(color: Color(0xFF7185A3), fontSize: 10),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                key: const Key('talk-end-button'),
                tooltip: 'End conversation',
                onPressed: onEnd,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFE11D48),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.call_end_rounded, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'AI-generated answers may be inaccurate. Verify important details.',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Color(0xFF596B84), fontSize: 9.5),
          ),
        ],
      ),
    ),
  );
}
