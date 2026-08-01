import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'timeline_news_item.dart';

Future<void> showNewsDetailsSheet(BuildContext context, TimelineNewsItem item) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: const Color(0xFF111827),
    builder: (context) => NewsDetailsSheet(item: item),
  );
}

class NewsDetailsSheet extends StatelessWidget {
  const NewsDetailsSheet({super.key, required this.item});

  final TimelineNewsItem item;

  Uri? get _articleUri {
    final uri = Uri.tryParse(item.url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri;
  }

  @override
  Widget build(BuildContext context) {
    final location = [
      item.place,
      item.country,
    ].where((value) => value.isNotEmpty).join(', ');
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    location.isEmpty ? 'Geolocated news' : location,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (item.pulseReady)
                  const Chip(
                    avatar: Icon(Icons.auto_awesome, size: 16),
                    label: Text('Ask AI ready'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _Detail(
              label: 'Source',
              value: item.source.isEmpty ? 'Unknown' : item.source,
            ),
            _Detail(label: 'Tone', value: item.tone.toStringAsFixed(2)),
            _Detail(label: 'AI-ready', value: item.pulseReady ? 'Yes' : 'No'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _articleUri == null
                    ? null
                    : () => launchUrl(
                        _articleUri!,
                        mode: LaunchMode.externalApplication,
                      ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open original article'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(label, style: const TextStyle(color: Colors.white60)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
