import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../timeline/timeline_news_item.dart';
import '../talk_news/talk_news_sheet.dart';
import 'article_details.dart';
import 'article_details_api.dart';
import 'article_language_selector.dart';
import 'article_summary_cache.dart';
import 'article_summary_controller.dart';

typedef ArticleLauncher = Future<bool> Function(Uri uri);

Future<void> showNewsDetailPopup({
  required BuildContext context,
  required TimelineNewsItem item,
  required String apiBaseUrl,
  required ArticleSummaryCache cache,
}) async {
  final controller = ArticleSummaryController(
    item: item,
    api: ArticleDetailsApi(baseUrl: apiBaseUrl),
    cache: cache,
  );
  unawaited(controller.load());

  try {
    final large = MediaQuery.sizeOf(context).width >= 700;
    if (large) {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.64),
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(32),
          backgroundColor: Colors.transparent,
          child: SafeArea(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
              child: NewsDetailPopup(
                controller: controller,
                apiBaseUrl: apiBaseUrl,
                onClose: () => Navigator.pop(dialogContext),
              ),
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: true,
        isDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.58),
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.42,
          maxChildSize: 0.95,
          snap: true,
          builder: (context, scrollController) => NewsDetailPopup(
            controller: controller,
            apiBaseUrl: apiBaseUrl,
            scrollController: scrollController,
            showDragHandle: true,
            onClose: () => Navigator.pop(sheetContext),
          ),
        ),
      );
    }
  } finally {
    controller.dispose();
  }
}

class NewsDetailPopup extends StatelessWidget {
  const NewsDetailPopup({
    super.key,
    required this.controller,
    required this.onClose,
    this.scrollController,
    this.showDragHandle = false,
    this.launcher,
    this.apiBaseUrl = '',
  });

  final ArticleSummaryController controller;
  final VoidCallback onClose;
  final ScrollController? scrollController;
  final bool showDragHandle;
  final ArticleLauncher? launcher;
  final String apiBaseUrl;

  Future<void> _openOriginal(BuildContext context) async {
    final uri = validatedHttpUri(controller.item.url);
    if (uri == null) {
      _showLaunchError(context);
      return;
    }
    final open =
        launcher ??
        (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
    try {
      if (!await open(uri) && context.mounted) _showLaunchError(context);
    } catch (_) {
      if (context.mounted) _showLaunchError(context);
    }
  }

  void _showLaunchError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open the original article.')),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final details = controller.details;
      final direction = controller.language.isRtl
          ? TextDirection.rtl
          : TextDirection.ltr;
      return Directionality(
        textDirection: direction,
        child: Material(
          key: const Key('news-detail-popup'),
          color: const Color(0xF2131B2B),
          elevation: 24,
          shadowColor: Colors.black87,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
            bottom: Radius.circular(22),
          ),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
                bottom: Radius.circular(22),
              ),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xF21B263A), Color(0xF20B1220)],
              ),
            ),
            child: CustomScrollView(
              controller: scrollController,
              shrinkWrap: true,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showDragHandle) const _DragHandle(),
                      _Header(
                        item: controller.item,
                        details: details,
                        languageSelector: ArticleLanguageSelector(
                          selected: controller.language,
                          onChanged: controller.selectLanguage,
                        ),
                        onClose: onClose,
                      ),
                      _ArticleVisual(
                        details: details,
                        loading: controller.isLoading,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                        child: _SummaryBody(controller: controller),
                      ),
                      _Footer(
                        talkEnabled:
                            supportsTalkToNews(controller.item) &&
                            apiBaseUrl.trim().isNotEmpty,
                        onTalk: () => showTalkNewsSheet(
                          context: context,
                          item: controller.item,
                          apiBaseUrl: apiBaseUrl,
                          title: controller.details?.title ?? '',
                        ),
                        originalEnabled:
                            validatedHttpUri(controller.item.url) != null,
                        onOpenOriginal: () => _openOriginal(context),
                        onClose: onClose,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 10, bottom: 2),
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white30,
        borderRadius: BorderRadius.circular(20),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.details,
    required this.languageSelector,
    required this.onClose,
  });

  final TimelineNewsItem item;
  final ArticleDetails? details;
  final Widget languageSelector;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final location = [
      item.place,
      item.country,
    ].where((part) => part.isNotEmpty).join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF60A5FA)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: Color(0xFF93C5FD),
                    ),
                    SizedBox(width: 5),
                    Text('AI summary', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const Spacer(),
              languageSelector,
              IconButton(
                key: const Key('popup-close-button'),
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                details?.emoji.isNotEmpty == true
                    ? details!.emoji
                    : '\u{1F4F0}',
                style: const TextStyle(fontSize: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      details?.title.isNotEmpty == true
                          ? details!.title
                          : (location.isEmpty ? 'Geolocated news' : location),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      item.source.isEmpty ? 'Unknown source' : item.source,
                      style: const TextStyle(color: Color(0xFFCBD5E1)),
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        location,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _TonePill(item: item),
            ],
          ),
        ],
      ),
    );
  }
}

class _TonePill extends StatelessWidget {
  const _TonePill({required this.item});
  final TimelineNewsItem item;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.color) {
      'red' => const Color(0xFFFF4D5E),
      'green' => const Color(0xFF00E88A),
      'yellow' => const Color(0xFFF6D44A),
      _ => const Color(0xFF67A8FF),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.75)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        item.tone.toStringAsFixed(1),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ArticleVisual extends StatelessWidget {
  const _ArticleVisual({required this.details, required this.loading});
  final ArticleDetails? details;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const AspectRatio(
        aspectRatio: 16 / 7,
        child: _LoadingSurface(key: Key('article-image-loading')),
      );
    }
    final uri = details?.imageUri;
    if (uri == null) return const _ImageFallback();
    return AspectRatio(
      aspectRatio: 16 / 8,
      child: Image.network(
        uri.toString(),
        key: const Key('article-image'),
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : const _LoadingSurface(),
        errorBuilder: (_, _, _) => const _ImageFallback(),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('article-image-fallback'),
    height: 116,
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFF172554), Color(0xFF111827)]),
    ),
    child: const Center(
      child: Icon(Icons.newspaper_rounded, size: 46, color: Color(0xFF64748B)),
    ),
  );
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.controller});
  final ArticleSummaryController controller;

  @override
  Widget build(BuildContext context) => switch (controller.status) {
    ArticleSummaryStatus.idle ||
    ArticleSummaryStatus.loading => const _SummaryLoading(),
    ArticleSummaryStatus.error => _SummaryError(onRetry: controller.retry),
    ArticleSummaryStatus.ready => _SummaryReady(details: controller.details!),
  };
}

class _SummaryLoading extends StatelessWidget {
  const _SummaryLoading();

  @override
  Widget build(BuildContext context) => const Column(
    key: Key('article-summary-loading'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Reading and summarizing the original article\u2026',
        style: TextStyle(color: Color(0xFFBFDBFE), fontWeight: FontWeight.w600),
      ),
      SizedBox(height: 14),
      _LoadingLine(widthFactor: 1),
      SizedBox(height: 9),
      _LoadingLine(widthFactor: 0.86),
      SizedBox(height: 9),
      _LoadingLine(widthFactor: 0.66),
      SizedBox(height: 20),
    ],
  );
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine({required this.widthFactor});
  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: widthFactor,
    child: const SizedBox(height: 13, child: _LoadingSurface()),
  );
}

class _LoadingSurface extends StatefulWidget {
  const _LoadingSurface({super.key});

  @override
  State<_LoadingSurface> createState() => _LoadingSurfaceState();
}

class _LoadingSurfaceState extends State<_LoadingSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      lowerBound: 0.35,
      upperBound: 0.85,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _animation,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF334155),
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );
}

class _SummaryError extends StatelessWidget {
  const _SummaryError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('article-summary-error'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF7F1D1D).withValues(alpha: 0.22),
      border: Border.all(color: const Color(0xFFF87171).withValues(alpha: 0.5)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: Color(0xFFFCA5A5)),
        const SizedBox(width: 12),
        const Expanded(child: Text('This article could not be summarized.')),
        TextButton.icon(
          key: const Key('article-retry-button'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _SummaryReady extends StatelessWidget {
  const _SummaryReady({required this.details});
  final ArticleDetails details;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('article-summary-ready'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SummarySection(
        key: const Key('summary-what-happened'),
        label: 'What happened',
        value: details.whatHappened,
        icon: Icons.bolt_rounded,
      ),
      const SizedBox(height: 12),
      _SummarySection(
        key: const Key('summary-when'),
        label: 'When',
        value: details.when,
        icon: Icons.schedule,
      ),
      const SizedBox(height: 12),
      _SummarySection(
        key: const Key('summary-where'),
        label: 'Where',
        value: details.where,
        icon: Icons.place_outlined,
      ),
      const SizedBox(height: 12),
      _SummarySection(
        key: const Key('summary-why'),
        label: 'Why',
        value: details.why,
        icon: Icons.help_outline,
      ),
      const SizedBox(height: 12),
      _SummarySection(
        key: const Key('summary-how'),
        label: 'How',
        value: details.how,
        icon: Icons.route_outlined,
      ),
    ],
  );
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF1D4ED8).withValues(alpha: 0.18),
      border: Border.all(color: const Color(0xFF60A5FA).withValues(alpha: 0.5)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: const Color(0xFF93C5FD)),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFBFDBFE),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value.isEmpty ? 'Not specified' : value,
          style: const TextStyle(height: 1.42, fontSize: 15),
        ),
      ],
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.talkEnabled,
    required this.onTalk,
    required this.originalEnabled,
    required this.onOpenOriginal,
    required this.onClose,
  });

  final bool talkEnabled;
  final VoidCallback onTalk;
  final bool originalEnabled;
  final VoidCallback onOpenOriginal;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'AI-generated summary. Verify important details with the original source.',
          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        if (talkEnabled) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0284C7), Color(0xFF4F46E5)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x553B82F6),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: FilledButton.icon(
              key: const Key('talk-to-news-button'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onTalk,
              icon: const Icon(Icons.graphic_eq_rounded),
              label: const Text(
                'Talk to this news',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('open-original-button'),
                onPressed: originalEnabled ? onOpenOriginal : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open original source'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              key: const Key('popup-footer-close-button'),
              onPressed: onClose,
              child: const Text('Close'),
            ),
          ],
        ),
      ],
    ),
  );
}
