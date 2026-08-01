import 'package:flutter/foundation.dart';

import 'timeline_news_api.dart';
import 'timeline_news_item.dart';
import 'timeline_selection.dart';

class TimelineController extends ChangeNotifier {
  TimelineController({
    required TimelineNewsApi api,
    TimelineSelection? initialSelection,
  }) : _api = api,
       _selection = initialSelection ?? TimelineSelection.latestCompleted();

  final TimelineNewsApi _api;
  TimelineSelection _selection;
  List<TimelineNewsItem> _items = const [];
  String? _error;
  bool _loading = false;
  bool _disposed = false;
  int _requestGeneration = 0;

  TimelineSelection get selection => _selection;
  List<TimelineNewsItem> get items => _items;
  String? get error => _error;
  bool get isLoading => _loading;
  bool get isInitialLoading => _loading && _items.isEmpty;
  bool get isEmpty => !_loading && _error == null && _items.isEmpty;

  Future<void> load() async {
    if (_disposed) return;
    final generation = ++_requestGeneration;
    _api.cancel();
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.fetch(_selection, preferCached: _items.isEmpty);
      if (_disposed || generation != _requestGeneration) return;
      _items = List.unmodifiable(result);
    } catch (error) {
      if (_disposed || generation != _requestGeneration) return;
      final message = error.toString();
      if (!message.contains('cancelled')) _error = message;
    } finally {
      if (!_disposed && generation == _requestGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> select(TimelineSelection selection) async {
    if (_disposed || selection.ist == _selection.ist) return;
    _selection = selection;
    await load();
  }

  void clearError() {
    if (_disposed || _error == null) return;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requestGeneration++;
    _api.dispose();
    super.dispose();
  }
}
