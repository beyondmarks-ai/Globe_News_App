import 'package:flutter/material.dart';

import 'article_language.dart';

class ArticleLanguageSelector extends StatelessWidget {
  const ArticleLanguageSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final ArticleLanguage selected;
  final ValueChanged<ArticleLanguage> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => DropdownButtonHideUnderline(
    child: DropdownButton<ArticleLanguage>(
      key: const Key('article-language-selector'),
      value: selected,
      borderRadius: BorderRadius.circular(14),
      dropdownColor: const Color(0xFF172033),
      icon: const Icon(Icons.translate, size: 18),
      isDense: true,
      onChanged: enabled
          ? (language) {
              if (language != null) onChanged(language);
            }
          : null,
      items: ArticleLanguage.values
          .map(
            (language) =>
                DropdownMenuItem(value: language, child: Text(language.label)),
          )
          .toList(growable: false),
    ),
  );
}
