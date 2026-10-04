import 'package:flutter/material.dart';

import 'basemap_selector.dart';
import 'map_basemap.dart';
import 'place_search/expandable_place_search.dart';
import 'place_search/place_search_controller.dart';
import 'place_search/place_search_result.dart';

class GlobeTopControls extends StatelessWidget {
  const GlobeTopControls({
    required this.searchController,
    required this.onPlaceSelected,
    required this.selectedBasemap,
    required this.isBasemapBusy,
    required this.onBasemapSelected,
    required this.alertsEnabled,
    required this.onAlertsPressed,
    this.searchKey,
    this.onAccountPressed,
    super.key,
  });

  final PlaceSearchController searchController;
  final ValueChanged<PlaceSearchResult> onPlaceSelected;
  final MapBasemap selectedBasemap;
  final bool isBasemapBusy;
  final ValueChanged<MapBasemap> onBasemapSelected;
  final bool alertsEnabled;
  final VoidCallback onAlertsPressed;
  final GlobalKey<ExpandablePlaceSearchState>? searchKey;
  final VoidCallback? onAccountPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onAccountPressed != null)
          IconButton.filledTonal(
            tooltip: 'Your account',
            onPressed: onAccountPressed,
            icon: const Icon(Icons.person_outline),
          ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: ExpandablePlaceSearch(
              key: searchKey,
              controller: searchController,
              onSelected: onPlaceSelected,
            ),
          ),
        ),
        const SizedBox(width: 8),
        BasemapSelector(
          key: const Key('basemap-selector'),
          selected: selectedBasemap,
          isBusy: isBasemapBusy,
          onSelected: onBasemapSelected,
          alertsEnabled: alertsEnabled,
          onAlertsPressed: onAlertsPressed,
        ),
      ],
    );
  }
}
