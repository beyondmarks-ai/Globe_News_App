import 'package:flutter/foundation.dart';

import 'place_search_api.dart';
import 'place_search_result.dart';

class PlaceSearchController extends ChangeNotifier {
  PlaceSearchController({required PlaceSearchClient api}) : _api = api;

  final PlaceSearchClient _api;
  bool _expanded = false;
  bool _loading = false;
  bool _disposed = false;
  int _requestId = 0;
  String? _message;

  bool get expanded => _expanded;
  bool get loading => _loading;
  String? get message => _message;

  void toggle() {
    if (_disposed) return;
    _expanded = !_expanded;
    _message = null;
    if (!_expanded) {
      _requestId++;
      _loading = false;
    }
    notifyListeners();
  }

  void collapse() {
    if (_disposed || !_expanded) return;
    _expanded = false;
    _loading = false;
    _message = null;
    _requestId++;
    notifyListeners();
  }

  Future<PlaceSearchResult?> submit(String query) async {
    final normalized = query.trim();
    if (_disposed || normalized.isEmpty || _loading) return null;

    final requestId = ++_requestId;
    _loading = true;
    _message = null;
    notifyListeners();
    try {
      final result = await _api.search(normalized);
      if (_disposed || requestId != _requestId) return null;
      _loading = false;
      _message = result == null ? 'Place not found' : result.name;
      notifyListeners();
      return result;
    } catch (_) {
      if (_disposed || requestId != _requestId) return null;
      _loading = false;
      _message = 'Search unavailable. Try again.';
      notifyListeners();
      return null;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requestId++;
    _api.dispose();
    super.dispose();
  }
}
