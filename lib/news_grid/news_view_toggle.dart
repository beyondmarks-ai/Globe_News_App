import 'package:flutter/material.dart';

import 'news_view_mode.dart';

class NewsViewToggle extends StatelessWidget {
  const NewsViewToggle({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final NewsViewMode selected;
  final ValueChanged<NewsViewMode> onSelected;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('news-view-toggle'),
    color: const Color(0xF20B1422),
    elevation: 10,
    shadowColor: Colors.black54,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleItem(
            key: const Key('globe-view-option'),
            icon: Icons.public_rounded,
            label: 'Globe',
            selected: selected == NewsViewMode.globe,
            onTap: () => onSelected(NewsViewMode.globe),
          ),
          _ToggleItem(
            key: const Key('grid-view-option'),
            icon: Icons.grid_view_rounded,
            label: 'News Grid',
            selected: selected == NewsViewMode.grid,
            onTap: () => onSelected(NewsViewMode.grid),
          ),
        ],
      ),
    ),
  );
}

class _ToggleItem extends StatelessWidget {
  const _ToggleItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: 'Show $label view',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      splashColor: Colors.white10,
      highlightColor: Colors.white.withValues(alpha: 0.04),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1D4ED8) : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? Colors.white : const Color(0xFF91A4BF),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFB8C4D8),
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
