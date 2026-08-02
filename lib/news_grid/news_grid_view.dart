import 'package:flutter/material.dart';

import '../timeline/timeline_news_item.dart';

class NewsGridView extends StatelessWidget {
  const NewsGridView({
    super.key,
    required this.items,
    required this.displayDate,
    required this.displayTime,
    required this.isLoading,
    required this.onRefresh,
    required this.onItemSelected,
    this.error,
  });

  final List<TimelineNewsItem> items;
  final String displayDate;
  final String displayTime;
  final bool isLoading;
  final String? error;
  final Future<void> Function() onRefresh;
  final ValueChanged<TimelineNewsItem> onItemSelected;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('news-grid-view'),
    color: const Color(0xFF060B14),
    child: SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: const Color(0xFF60A5FA),
        backgroundColor: const Color(0xFF111827),
        child: CustomScrollView(
          key: const PageStorageKey('timeline-news-grid'),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              sliver: SliverToBoxAdapter(
                child: _GridHeader(
                  count: items.length,
                  displayDate: displayDate,
                  displayTime: displayTime,
                ),
              ),
            ),
            if (isLoading)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(
                  key: Key('news-grid-progress'),
                  minHeight: 2,
                  color: Color(0xFF3B82F6),
                  backgroundColor: Colors.transparent,
                ),
              ),
            if (error != null && items.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: _InlineError(message: error!),
                ),
              ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyGrid(isLoading: isLoading, error: error),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 190),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  itemBuilder: (context, index) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: NewsGridCard(
                        item: items[index],
                        onTap: () => onItemSelected(items[index]),
                      ),
                    ),
                  ),
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 11),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _GridHeader extends StatelessWidget {
  const _GridHeader({
    required this.count,
    required this.displayDate,
    required this.displayTime,
  });

  final int count;
  final String displayDate;
  final String displayTime;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NEWSROOM',
              style: TextStyle(
                color: Color(0xFF60A5FA),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Stories around the world',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFFF3F6FC),
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$count ${count == 1 ? 'story' : 'stories'}',
            style: const TextStyle(
              color: Color(0xFFD7E2F2),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$displayDate · $displayTime IST',
            style: const TextStyle(color: Color(0xFF7F91AA), fontSize: 11),
          ),
        ],
      ),
    ],
  );
}

class NewsGridCard extends StatelessWidget {
  const NewsGridCard({super.key, required this.item, required this.onTap});

  final TimelineNewsItem item;
  final VoidCallback onTap;

  Color get _toneColor => switch (item.color) {
    'red' => const Color(0xFFFF4D5E),
    'green' => const Color(0xFF00E88A),
    'yellow' => const Color(0xFFF6D44A),
    _ => const Color(0xFF67A8FF),
  };

  String get _toneLabel => switch (item.color) {
    'red' => 'NEGATIVE',
    'green' => 'POSITIVE',
    'yellow' => 'NEUTRAL',
    _ => 'NEWS',
  };

  String get _headline {
    if (item.headline.isNotEmpty) return item.headline;
    final source = item.source.trim();
    return source.isEmpty ? 'Latest news story' : 'Latest from $source';
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Open news from ${item.place}, ${item.country}',
    child: Material(
      key: Key('news-card-${item.id}'),
      color: const Color(0xFF0B1421),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: _toneColor.withValues(alpha: 0.1),
        highlightColor: Colors.white.withValues(alpha: 0.025),
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF1B293B)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 3, child: ColoredBox(color: _toneColor)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(15, 13, 13, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.source.isEmpty
                                    ? 'NEWS SOURCE'
                                    : item.source.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF8EA1BB),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            Icon(Icons.circle, size: 6, color: _toneColor),
                            const SizedBox(width: 5),
                            Text(
                              _toneLabel,
                              style: TextStyle(
                                color: _toneColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _headline,
                          key: const Key('news-headline'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF4F7FC),
                            fontSize: 17.5,
                            height: 1.22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.25,
                          ),
                        ),
                        const SizedBox(height: 11),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: Color(0xFF7185A1),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                [
                                  item.place,
                                  item.country,
                                ].where((part) => part.isNotEmpty).join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF8295AF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (item.aiReady) ...[
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 12,
                                color: Color(0xFFA78BFA),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'AI READY',
                                style: TextStyle(
                                  color: Color(0xFFAFA1E8),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.55,
                                ),
                              ),
                            ],
                            const SizedBox(width: 7),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 15,
                              color: Color(0xFF7185A1),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _EmptyGrid extends StatelessWidget {
  const _EmptyGrid({required this.isLoading, required this.error});

  final bool isLoading;
  final String? error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 180),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            const CircularProgressIndicator(strokeWidth: 2.5)
          else
            Icon(
              error == null
                  ? Icons.dynamic_feed_outlined
                  : Icons.cloud_off_rounded,
              size: 42,
              color: const Color(0xFF6F84A2),
            ),
          const SizedBox(height: 14),
          Text(
            isLoading
                ? 'Loading stories…'
                : error ?? 'No stories are available for this timeline slot.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFA8B7CB), height: 1.4),
          ),
          if (!isLoading) ...[
            const SizedBox(height: 10),
            const Text(
              'Pull down to refresh',
              style: TextStyle(color: Color(0xFF60738E), fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24)),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFFC5D0DF), fontSize: 12),
        ),
      ),
    ],
  );
}
