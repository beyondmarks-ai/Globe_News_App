import 'package:flutter/material.dart';

import '../article/article_summary_cache.dart';
import '../article/news_detail_popup.dart';
import 'topic_search_api.dart';
import 'topic_search_controller.dart';

class TopicSearchScreen extends StatefulWidget {
  const TopicSearchScreen({super.key, required this.apiBaseUrl, this.client});
  final String apiBaseUrl;
  final TopicSearchClient? client;

  @override
  State<TopicSearchScreen> createState() => _TopicSearchScreenState();
}

class _TopicSearchScreenState extends State<TopicSearchScreen> {
  final _text = TextEditingController();
  final _cache = ArticleSummaryCache();
  late final TopicSearchController _search;

  @override
  void initState() {
    super.initState();
    _search = TopicSearchController(
      widget.client ?? TopicSearchApi(baseUrl: widget.apiBaseUrl),
    );
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    _search.search(_text.text);
  }

  @override
  void dispose() {
    _text.dispose();
    _search.dispose();
    super.dispose();
  }

  String _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? 'unknown'
        : parsed.toUtc().toIso8601String().substring(0, 10);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search news')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: AnimatedBuilder(
            animation: _search,
            builder: (context, _) => CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Follow a topic, across time.',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ask about a topic, person or event. No date selection needed.',
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          key: const Key('topic-query'),
                          controller: _text,
                          textInputAction: TextInputAction.search,
                          maxLength: 200,
                          onChanged: (_) => _search.edit(),
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'What news are you looking for?',
                            hintText: 'e.g. war in Iran',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              key: const Key('topic-submit'),
                              tooltip: 'Search news',
                              onPressed: _submit,
                              icon: const Icon(Icons.search),
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Chip(
                              avatar: Icon(Icons.history, size: 18),
                              label: Text('Any time'),
                            ),
                            DropdownButton<String>(
                              value: _search.sort,
                              items: const [
                                DropdownMenuItem(
                                  value: 'relevance',
                                  child: Text('Most relevant'),
                                ),
                                DropdownMenuItem(
                                  value: 'newest',
                                  child: Text('Newest observed'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  _search.search(_text.text, order: value);
                                }
                              },
                            ),
                          ],
                        ),
                        if (!_search.searched) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final example in [
                                'war in Iran',
                                'climate change',
                                'India',
                              ])
                                ActionChip(
                                  label: Text(example),
                                  onPressed: () {
                                    _text.text = example;
                                    _submit();
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Searches our saved headlines, URL keywords and locations. Coverage depends on collected news; not every article ever published is available.',
                          ),
                        ],
                        if (_search.coverage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            '${_search.total} matching articles • ${_search.items.length} shown',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Archive: ${_date(_search.coverage!['from'])} – ${_date(_search.coverage!['to'])} (UTC). Dates are first observed, not publication dates.',
                          ),
                          if (_search.coverage!['backfillComplete'] != true)
                            const Text(
                              'Older saved stories are still being indexed. More results will become available.',
                            ),
                        ],
                        if (_search.loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: LinearProgressIndicator(),
                          ),
                        if (_search.error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_search.error!),
                                TextButton(
                                  onPressed: () => _search.search(
                                    _text.text,
                                    more:
                                        _search.items.isNotEmpty &&
                                        !_search.restartRequired,
                                  ),
                                  child: Text(
                                    _search.restartRequired
                                        ? 'Search again'
                                        : 'Retry',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_search.searched &&
                            !_search.loading &&
                            _search.error == null &&
                            _search.items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              'No matching stories in the available archive. Try fewer keywords or another name for the topic.',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: _search.items.length,
                    itemBuilder: (context, index) {
                      final story = _search.items[index];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Text(story.item.headline),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${story.item.source}\nFirst observed ${_date(story.firstSeen)} UTC${story.titleInferred ? '\nTitle derived from article link' : ''}',
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => showNewsDetailPopup(
                            context: context,
                            item: story.item,
                            apiBaseUrl: widget.apiBaseUrl,
                            cache: _cache,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _search.cursor != null && !_search.restartRequired
                        ? Center(
                            child: OutlinedButton(
                              key: const Key('topic-load-more'),
                              onPressed: _search.loading
                                  ? null
                                  : () =>
                                        _search.search(_text.text, more: true),
                              child: const Text('Load more'),
                            ),
                          )
                        : const SizedBox(height: 12),
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
