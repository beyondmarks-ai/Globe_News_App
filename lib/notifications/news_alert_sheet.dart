import 'package:flutter/material.dart';

import '../place_search/place_search_api.dart';
import '../place_search/place_search_result.dart';
import 'news_alert.dart';
import 'news_alert_controller.dart';

Future<void> showNewsAlertSheet({
  required BuildContext context,
  required NewsAlertController controller,
  required String mapboxAccessToken,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: const Color(0xB3030712),
  builder: (_) => NewsAlertSheet(
    controller: controller,
    mapboxAccessToken: mapboxAccessToken,
  ),
);

class NewsAlertSheet extends StatefulWidget {
  const NewsAlertSheet({
    required this.controller,
    required this.mapboxAccessToken,
    super.key,
  });

  final NewsAlertController controller;
  final String mapboxAccessToken;

  @override
  State<NewsAlertSheet> createState() => _NewsAlertSheetState();
}

class _NewsAlertSheetState extends State<NewsAlertSheet> {
  late final PlaceSearchApi _searchApi;
  late final TextEditingController _query;
  late final FocusNode _focus;
  PlaceSearchResult? _place;
  List<PlaceSearchResult> _results = const [];
  String? _searchError;
  bool _searching = false;
  late int _radius;
  late String _language;
  late NewsAlertMode _mode;
  late NewsAlertScope _scope;
  late bool _quietHours;

  @override
  void initState() {
    super.initState();
    _searchApi = PlaceSearchApi(
      accessToken: widget.mapboxAccessToken,
      permanentStorage: true,
    );
    _focus = FocusNode();
    final alert = widget.controller.alert;
    _query = TextEditingController(text: alert?.locationLabel ?? '');
    if (alert != null) {
      _place = PlaceSearchResult(
        name: alert.locationLabel,
        longitude: alert.longitude,
        latitude: alert.latitude,
        featureType: alert.locationType,
        boundingBox: alert.boundingBox,
      );
    }
    _radius = alert?.radiusMeters ?? 25000;
    _language = alert?.language ?? 'en-US';
    _mode = alert?.mode ?? NewsAlertMode.smart;
    _scope = alert?.scope ?? NewsAlertScope.administrativeBounds;
    _quietHours = alert?.quietHoursEnabled ?? true;
  }

  @override
  void dispose() {
    _searchApi.dispose();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final text = _query.text.trim();
    if (text.length < 2 || _searching) {
      setState(() => _searchError = 'Enter a city or state name.');
      return;
    }
    _focus.unfocus();
    setState(() {
      _searching = true;
      _results = const [];
      _searchError = null;
    });
    try {
      final results = await _searchApi.searchMany(
        text,
        types: 'region,district,place,locality',
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _searchError = results.isEmpty
            ? 'No matching city or state was found.'
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _searchError = 'Place search is unavailable. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _select(PlaceSearchResult place) {
    setState(() {
      _place = place;
      _query.text = place.name;
      _results = const [];
      _scope = place.hasAdministrativeBounds
          ? NewsAlertScope.administrativeBounds
          : NewsAlertScope.customRadius;
      _radius = place.featureType == 'region' ? 100000 : 25000;
      _searchError = null;
    });
  }

  Future<void> _save() async {
    final place = _place;
    if (place == null) {
      setState(() => _searchError = 'Select a city or state first.');
      return;
    }
    final scope =
        _scope == NewsAlertScope.administrativeBounds &&
            place.hasAdministrativeBounds
        ? _scope
        : NewsAlertScope.customRadius;
    final saved = await widget.controller.save(
      NewsAlert(
        latitude: place.latitude,
        longitude: place.longitude,
        locationLabel: place.name,
        locationType: place.featureType,
        scope: scope,
        boundingBox: place.boundingBox,
        radiusMeters: _radius,
        language: _language,
        mode: _mode,
        quietHoursEnabled: _quietHours,
      ),
    );
    if (!mounted || !saved) return;
    Navigator.of(context).pop();
    final coverage = scope == NewsAlertScope.customRadius
        ? 'within ${_radius ~/ 1000} km of ${place.name}'
        : 'across ${place.name}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('News alerts enabled $coverage.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.62,
        maxChildSize: 0.96,
        builder: (context, scrollController) => DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFF091321),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Color(0xFF2D4168))),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              _header(),
              const SizedBox(height: 8),
              const _Label(
                'Choose an area',
                'Search for a city, district, or state',
              ),
              const SizedBox(height: 10),
              _searchField(),
              if (_searchError case final error?) ...[
                const SizedBox(height: 8),
                Text(error, style: const TextStyle(color: Color(0xFFFCA5A5))),
              ],
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 8),
                _resultsPanel(),
              ],
              if (_place case final place?) ...[
                const SizedBox(height: 14),
                _selectedPlace(place),
                const SizedBox(height: 22),
                const _Label(
                  'Coverage',
                  'Follow the whole area or add a radius',
                ),
                const SizedBox(height: 10),
                _ScopeOption(
                  icon: Icons.map_outlined,
                  title: 'Whole ${_typeName(place).toLowerCase()} area',
                  subtitle: place.hasAdministrativeBounds
                      ? 'Uses verified Mapbox administrative bounds'
                      : 'Bounds unavailable for this result',
                  selected: _scope == NewsAlertScope.administrativeBounds,
                  enabled: place.hasAdministrativeBounds,
                  onTap: () => setState(
                    () => _scope = NewsAlertScope.administrativeBounds,
                  ),
                ),
                const SizedBox(height: 8),
                _ScopeOption(
                  icon: Icons.radar_rounded,
                  title: 'Custom radius',
                  subtitle: 'Notify around the selected area centre',
                  selected: _scope == NewsAlertScope.customRadius,
                  enabled: true,
                  onTap: () =>
                      setState(() => _scope = NewsAlertScope.customRadius),
                ),
                if (_scope == NewsAlertScope.customRadius) ...[
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _radii(place)
                        .map(
                          (value) => ChoiceChip(
                            label: Text('${value ~/ 1000} km'),
                            selected: _radius == value,
                            onSelected: (_) => setState(() => _radius = value),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
              const SizedBox(height: 22),
              const _Label('Language', 'AI-refined notification headlines'),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: _decoration(),
                dropdownColor: const Color(0xFF101C2D),
                items: NewsAlert.supportedLanguages.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _language = value);
                },
              ),
              const SizedBox(height: 22),
              const _Label('Delivery', 'Smart mode groups nearby updates'),
              const SizedBox(height: 10),
              SegmentedButton<NewsAlertMode>(
                segments: const [
                  ButtonSegment(
                    value: NewsAlertMode.smart,
                    label: Text('Smart'),
                  ),
                  ButtonSegment(
                    value: NewsAlertMode.immediate,
                    label: Text('Instant'),
                  ),
                  ButtonSegment(
                    value: NewsAlertMode.digest,
                    label: Text('Digest'),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => _mode = value.first),
              ),
              SwitchListTile.adaptive(
                value: _quietHours,
                contentPadding: EdgeInsets.zero,
                title: const Text('Quiet hours'),
                subtitle: const Text('Pause alerts from 10 PM to 7 AM'),
                onChanged: (value) => setState(() => _quietHours = value),
              ),
              if (widget.controller.error case final error?)
                Text(error, style: const TextStyle(color: Color(0xFFFCA5A5))),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('save-news-alert'),
                onPressed: widget.controller.busy || _place == null
                    ? null
                    : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: widget.controller.busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.notifications_active_outlined),
                label: Text(
                  widget.controller.alert == null
                      ? 'Enable area alerts'
                      : 'Update area alert',
                ),
              ),
              if (widget.controller.alert != null)
                TextButton(
                  onPressed: widget.controller.busy
                      ? null
                      : () async {
                          final disabled = await widget.controller.disable();
                          if (!context.mounted || !disabled) return;
                          Navigator.of(context).pop();
                        },
                  child: const Text(
                    'Turn off alerts',
                    style: TextStyle(color: Color(0xFFFCA5A5)),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'Your selected area is stored for notifications. '
                'Globe News never tracks background location.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8494B2), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _header() => Row(
    children: [
      const CircleAvatar(
        backgroundColor: Color(0x2622D3EE),
        child: Icon(
          Icons.notifications_active_outlined,
          color: Color(0xFF67E8F9),
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Area News Alerts',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            Text(
              'Choose a city or state to follow',
              style: TextStyle(color: Color(0xFFAAB7D4), fontSize: 13),
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Close',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close_rounded),
      ),
    ],
  );

  Widget _searchField() => TextField(
    key: const Key('alert-place-search-field'),
    controller: _query,
    focusNode: _focus,
    textInputAction: TextInputAction.search,
    onSubmitted: (_) => _runSearch(),
    onChanged: (_) {
      if (_place != null) setState(() => _place = null);
    },
    decoration: _decoration().copyWith(
      hintText: 'Search city or state',
      prefixIcon: const Icon(
        Icons.location_city_rounded,
        color: Color(0xFF8EC5FF),
      ),
      suffixIcon: _searching
          ? const Padding(
              padding: EdgeInsets.all(15),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : IconButton(
              tooltip: 'Search',
              onPressed: _runSearch,
              icon: const Icon(Icons.search_rounded),
            ),
    ),
  );

  Widget _resultsPanel() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF101C2D),
      border: Border.all(color: const Color(0xFF263A5C)),
      borderRadius: BorderRadius.circular(16),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < _results.length; index++) ...[
          ListTile(
            leading: const Icon(
              Icons.location_on_outlined,
              color: Color(0xFF8EC5FF),
            ),
            title: Text(
              _results[index].name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _results[index].description.isEmpty
                ? Text(_typeName(_results[index]))
                : Text(
                    _results[index].description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _select(_results[index]),
          ),
          if (index != _results.length - 1)
            const Divider(height: 1, indent: 56),
        ],
      ],
    ),
  );

  Widget _selectedPlace(PlaceSearchResult place) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0x1422D3EE),
      border: Border.all(color: const Color(0x6638BDF8)),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        const Icon(Icons.check_circle_rounded, color: Color(0xFF67E8F9)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            place.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          _typeName(place),
          style: const TextStyle(
            color: Color(0xFF67E8F9),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ],
    ),
  );

  List<int> _radii(PlaceSearchResult place) => place.featureType == 'region'
      ? const [25000, 50000, 100000, 250000]
      : const [2000, 5000, 10000, 25000, 50000];

  String _typeName(PlaceSearchResult place) => switch (place.featureType) {
    'region' => 'STATE',
    'district' => 'DISTRICT',
    'place' || 'locality' => 'CITY',
    _ => 'AREA',
  };

  InputDecoration _decoration() => InputDecoration(
    filled: true,
    fillColor: const Color(0xFF101C2D),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF263A5C)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF263A5C)),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF8FA1BE), fontSize: 12),
      ),
    ],
  );
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.45,
    child: Material(
      color: selected ? const Color(0x1F3B82F6) : const Color(0xFF101C2D),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? const Color(0xFF3B82F6)
                  : const Color(0xFF263A5C),
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF8EC5FF)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF8FA1BE),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF64748B),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
