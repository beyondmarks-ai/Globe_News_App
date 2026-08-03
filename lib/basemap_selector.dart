import 'package:flutter/material.dart';

import 'map_basemap.dart';

class BasemapSelector extends StatelessWidget {
  const BasemapSelector({
    super.key,
    required this.selected,
    required this.isBusy,
    required this.onSelected,
    required this.alertsEnabled,
    required this.onAlertsPressed,
  });

  final MapBasemap selected;
  final bool isBusy;
  final ValueChanged<MapBasemap> onSelected;
  final bool alertsEnabled;
  final VoidCallback onAlertsPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xE6111827),
      elevation: 8,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BasemapButton(
            tooltip: 'Dark map',
            icon: Icons.public,
            selected: selected == MapBasemap.dark,
            enabled: !isBusy,
            onPressed: () => onSelected(MapBasemap.dark),
          ),
          Container(width: 1, height: 28, color: Colors.white12),
          _BasemapButton(
            tooltip: 'Satellite imagery',
            icon: Icons.satellite_alt_outlined,
            selected: selected == MapBasemap.satellite,
            enabled: !isBusy,
            onPressed: () => onSelected(MapBasemap.satellite),
          ),
          Container(width: 1, height: 28, color: Colors.white12),
          _BasemapButton(
            tooltip: alertsEnabled
                ? 'Nearby alert active'
                : 'Nearby news alerts',
            icon: alertsEnabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_rounded,
            selected: alertsEnabled,
            enabled: true,
            onPressed: onAlertsPressed,
          ),
          if (isBusy)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF93C5FD),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BasemapButton extends StatelessWidget {
  const _BasemapButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      visualDensity: VisualDensity.compact,
      color: selected ? const Color(0xFFBFDBFE) : Colors.white70,
      disabledColor: Colors.white30,
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? const Color(0x334B91E2)
            : Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}
