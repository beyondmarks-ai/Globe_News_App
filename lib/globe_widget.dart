import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'article/article_summary_cache.dart';
import 'article/news_detail_popup.dart';
import 'globe_top_controls.dart';
import 'globe_map_controller.dart';
import 'map_styles.dart';
import 'news_grid/news_grid_view.dart';
import 'news_grid/news_view_mode.dart';
import 'news_grid/news_view_toggle.dart';
import 'notifications/news_alert_api.dart';
import 'notifications/news_alert_controller.dart';
import 'notifications/news_alert_sheet.dart';
import 'notifications/news_notification_service.dart';
import 'place_search/expandable_place_search.dart';
import 'place_search/place_search_api.dart';
import 'place_search/place_search_controller.dart';
import 'place_search/place_search_result.dart';
import 'timeline/timeline_controller.dart';
import 'timeline/timeline_controls.dart';
import 'timeline/timeline_map_layer_manager.dart';
import 'timeline/timeline_news_api.dart';
import 'timeline/timeline_news_item.dart';
import 'news_demo/news_demo_screen.dart';

const timelineApiBaseUrl = String.fromEnvironment('API_BASE_URL');
const _mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

class GlobeWidget extends StatefulWidget {
  const GlobeWidget({
    this.rotationSuspended = false,
    this.newsAlerts,
    this.onAccountPressed,
    super.key,
  });

  final bool rotationSuspended;
  final NewsAlertController? newsAlerts;
  final VoidCallback? onAccountPressed;

  @override
  State<GlobeWidget> createState() => _GlobeWidgetState();
}

class _GlobeWidgetState extends State<GlobeWidget> with WidgetsBindingObserver {
  late final GlobeMapController _globeController;
  late final TimelineController _timelineController;
  late final TimelineMapLayerManager _timelineLayers;
  late final ArticleSummaryCache _articleSummaryCache;
  late final PlaceSearchController _placeSearchController;
  late final NewsAlertController _newsAlertController;
  StreamSubscription<NewsNotificationAction>? _notificationOpenedSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  NewsNotificationAction? _pendingNotificationAction;
  final GlobalKey<ExpandablePlaceSearchState> _searchKey = GlobalKey();
  List<TimelineNewsItem>? _lastSyncedItems;
  NewsViewMode _viewMode = NewsViewMode.globe;

  @override
  void initState() {
    super.initState();
    _globeController = GlobeMapController();
    _globeController.setRotationSuspended(widget.rotationSuspended);
    _globeController.addListener(_onGlobeChanged);
    _timelineController = TimelineController(
      api: TimelineNewsApi(baseUrl: timelineApiBaseUrl),
    )..addListener(_onTimelineChanged);
    _articleSummaryCache = ArticleSummaryCache();
    _placeSearchController = PlaceSearchController(
      api: PlaceSearchApi(accessToken: _mapboxAccessToken),
    );
    _newsAlertController =
        widget.newsAlerts ??
        NewsAlertController(api: NewsAlertApi(baseUrl: timelineApiBaseUrl));
    _newsAlertController.addListener(_onNewsAlertChanged);
    if (widget.newsAlerts == null) unawaited(_newsAlertController.load());
    _notificationOpenedSubscription = NewsNotificationService.instance.opened
        .listen(_handleNotificationAction);
    _foregroundMessageSubscription = NewsNotificationService
        .instance
        .foregroundMessages
        .listen(_showForegroundNotification);
    _pendingNotificationAction = NewsNotificationService.instance
        .takeInitialAction();
    _timelineLayers = TimelineMapLayerManager(onItemTapped: _showNewsItem);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_timelineController.load());
  }

  @override
  void didUpdateWidget(covariant GlobeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rotationSuspended != widget.rotationSuspended) {
      _globeController.setRotationSuspended(widget.rotationSuspended);
    }
  }

  void _onGlobeChanged() {
    if (mounted) setState(() {});
  }

  void _onNewsAlertChanged() {
    if (mounted) setState(() {});
  }

  void _onTimelineChanged() {
    final items = _timelineController.items;
    if (!identical(items, _lastSyncedItems)) {
      _lastSyncedItems = items;
      unawaited(_timelineLayers.setItems(items));
    }
    final pending = _pendingNotificationAction;
    if (pending != null && items.isNotEmpty) {
      _pendingNotificationAction = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleNotificationAction(pending),
      );
    }
    if (mounted) setState(() {});
  }

  void _showNewsItem(TimelineNewsItem item) {
    if (!mounted) return;
    _globeController.setRotationSuspended(true);
    unawaited(_openNewsItem(item));
  }

  Future<void> _openNewsItem(TimelineNewsItem item) async {
    try {
      await showNewsDetailPopup(
        context: context,
        item: item,
        apiBaseUrl: timelineApiBaseUrl,
        cache: _articleSummaryCache,
      );
    } finally {
      _globeController.setRotationSuspended(_viewMode == NewsViewMode.grid);
    }
  }

  void _setViewMode(NewsViewMode mode) {
    if (_viewMode == mode) return;
    _searchKey.currentState?.handleMapTap();
    setState(() => _viewMode = mode);
    _globeController.setRotationSuspended(mode == NewsViewMode.grid);
  }

  void _onMapCreated(MapboxMap map) {
    _globeController.attach(map);
    _timelineLayers.attach(map);
  }

  void _onPlaceSelected(PlaceSearchResult place) {
    unawaited(_globeController.flyToPlace(place));
  }

  Future<void> _showTopicSearch() async {
    _searchKey.currentState?.handleMapTap();
    _globeController.setRotationSuspended(true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => const NewsDemoScreen(apiBaseUrl: timelineApiBaseUrl),
        ),
      );
    } finally {
      if (mounted) {
        _globeController.setRotationSuspended(_viewMode == NewsViewMode.grid);
      }
    }
  }

  Future<void> _showNewsAlerts() async {
    _searchKey.currentState?.handleMapTap();
    _globeController.setRotationSuspended(true);
    try {
      await showNewsAlertSheet(
        context: context,
        controller: _newsAlertController,
        mapboxAccessToken: _mapboxAccessToken,
      );
    } finally {
      _globeController.setRotationSuspended(_viewMode == NewsViewMode.grid);
    }
  }

  void _handleNotificationAction(NewsNotificationAction action) {
    if (!mounted) return;
    final storyId = action.storyId;
    if (storyId != null) {
      for (final item in _timelineController.items) {
        if (item.id == storyId) {
          _showNewsItem(item);
          return;
        }
      }
    }
    _setViewMode(NewsViewMode.grid);
  }

  void _showForegroundNotification(RemoteMessage message) {
    if (!mounted) return;
    final notification = message.notification;
    final text = notification?.body ?? notification?.title;
    if (text == null || text.trim().isEmpty) return;
    final action = NewsNotificationAction.fromMessage(message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'View',
          onPressed: () => _handleNotificationAction(action),
        ),
      ),
    );
  }

  Future<void> _onStyleLoaded() async {
    await _globeController.onStyleLoaded();
    await _timelineLayers.onStyleLoaded();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _globeController.setAppActive(active);
    if (active) unawaited(_newsAlertController.reconnect());
    if (!active) _searchKey.currentState?.dismissForBackground();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _globeController
      ..removeListener(_onGlobeChanged)
      ..dispose();
    _timelineController
      ..removeListener(_onTimelineChanged)
      ..dispose();
    _timelineLayers.dispose();
    _placeSearchController.dispose();
    _newsAlertController.removeListener(_onNewsAlertChanged);
    if (widget.newsAlerts == null) _newsAlertController.dispose();
    unawaited(_notificationOpenedSubscription?.cancel());
    unawaited(_foregroundMessageSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _placeSearchController,
      builder: (context, child) => PopScope<Object?>(
        canPop:
            !_placeSearchController.expanded && _viewMode == NewsViewMode.globe,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_placeSearchController.expanded) {
            _searchKey.currentState?.handleBack();
          } else {
            _setViewMode(NewsViewMode.globe);
          }
        },
        child: child!,
      ),
      child: ColoredBox(
        color: const Color(0xFF030712),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) {
                _searchKey.currentState?.handleMapTap();
                _globeController.onInteractionStart();
              },
              onPointerUp: (_) => _globeController.onInteractionEnd(),
              onPointerCancel: (_) => _globeController.onInteractionEnd(),
              child: MapWidget(
                key: const ValueKey('native-globe-map'),
                styleUri: GlobeMapStyles.darkStyleUri,
                viewport: CameraViewportState(
                  center: Point(coordinates: Position(0, 20)),
                  zoom: 1.5,
                  bearing: 0,
                  pitch: 0,
                ),
                onMapCreated: _onMapCreated,
                onStyleLoadedListener: (_) => _onStyleLoaded(),
                onCameraChangeListener: (event) =>
                    _globeController.onCameraChanged(event.cameraState),
                onScrollListener: (_) =>
                    _globeController.registerUserActivity(),
                onZoomListener: (_) {
                  _globeController.disableAutoRotationForSession();
                  _globeController.registerUserActivity();
                },
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _viewMode == NewsViewMode.grid
                  ? NewsGridView(
                      key: const ValueKey('news-grid-surface'),
                      items: _timelineController.items,
                      displayDate: _timelineController.selection.displayDate,
                      displayTime: _timelineController.selection.displayTime,
                      isLoading: _timelineController.isLoading,
                      error: _timelineController.error,
                      onRefresh: _timelineController.load,
                      onItemSelected: _showNewsItem,
                    )
                  : const SizedBox.expand(
                      key: ValueKey('globe-overlay-surface'),
                    ),
            ),
            if (_viewMode == NewsViewMode.globe)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: GlobeTopControls(
                      searchKey: _searchKey,
                      searchController: _placeSearchController,
                      onPlaceSelected: _onPlaceSelected,
                      selectedBasemap: _globeController.basemap,
                      isBasemapBusy: _globeController.isChangingBasemap,
                      onBasemapSelected: _globeController.setBasemap,
                      alertsEnabled: _newsAlertController.notificationsEnabled,
                      onAlertsPressed: _showNewsAlerts,
                      onAccountPressed: widget.onAccountPressed,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 34,
              child: SafeArea(
                top: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.tonalIcon(
                        key: const Key('open-topic-search'),
                        onPressed: _showTopicSearch,
                        icon: const Icon(Icons.manage_search),
                        label: const Text('Ask the news • 1-day demo'),
                      ),
                      const SizedBox(height: 8),
                      NewsViewToggle(
                        selected: _viewMode,
                        onSelected: _setViewMode,
                      ),
                      const SizedBox(height: 8),
                      TimelineControls(controller: _timelineController),
                    ],
                  ),
                ),
              ),
            ),
            if (_viewMode == NewsViewMode.globe &&
                _timelineController.isInitialLoading)
              const Center(
                child: _StatusCard(
                  icon: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  message: 'Loading timeline news\u2026',
                ),
              )
            else if (_viewMode == NewsViewMode.globe &&
                _timelineController.isEmpty)
              const Center(
                child: _StatusCard(
                  icon: Icon(Icons.public_off_outlined),
                  message: 'No geolocated stories for this 15-minute slot.',
                ),
              )
            else if (_viewMode == NewsViewMode.globe &&
                _timelineController.error != null &&
                _timelineController.items.isEmpty)
              Center(
                child: _StatusCard(
                  icon: const Icon(Icons.cloud_off, color: Color(0xFFFBBF24)),
                  message: _timelineController.error!,
                  action: TextButton.icon(
                    onPressed: _timelineController.load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
              ),
            if (_viewMode == NewsViewMode.globe &&
                _timelineController.error != null &&
                _timelineController.items.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 112,
                child: _ErrorBanner(
                  message: _timelineController.error!,
                  onRetry: _timelineController.load,
                  onDismiss: _timelineController.clearError,
                ),
              ),
            if (_viewMode == NewsViewMode.globe)
              if (_globeController.lastError case final error?)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 112,
                  child: _ErrorBanner(
                    message: error,
                    onDismiss: _globeController.clearError,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.icon, required this.message, this.action});
  final Widget icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xE6111827),
    borderRadius: BorderRadius.circular(14),
    elevation: 8,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 290),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
    this.onRetry,
  });

  final String message;
  final VoidCallback onDismiss;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Material(
      color: const Color(0xF01F2937),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 13)),
            ),
            if (onRetry != null)
              IconButton(
                tooltip: 'Retry',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, color: Colors.white70),
              ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: const Icon(Icons.close, color: Colors.white70),
            ),
          ],
        ),
      ),
    ),
  );
}
