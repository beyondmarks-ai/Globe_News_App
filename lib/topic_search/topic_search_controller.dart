import 'package:flutter/foundation.dart';
import 'topic_search_api.dart';

class TopicSearchController extends ChangeNotifier {
  TopicSearchController(this.api);
  final TopicSearchClient api;
  List<TopicStory> items = [];
  Map<String, dynamic>? coverage;
  String query = '';
  String sort = 'relevance';
  String? cursor;
  String? error;
  int total = 0;
  bool loading = false;
  bool searched = false;
  bool restartRequired = false;
  bool _disposed = false;
  int _generation = 0;

  void edit() {
    _generation++;
    api.cancel();
    items = [];
    coverage = null;
    cursor = null;
    error = null;
    loading = false;
    searched = false;
    restartRequired = false;
    total = 0;
    notifyListeners();
  }

  Future<void> search(String value, {String? order, bool more = false}) async {
    if (_disposed || (more && (loading || cursor == null || restartRequired))) {
      return;
    }
    if (!more) {
      edit();
      query = value.trim();
      sort = order ?? sort;
      if (query.length < 2 || query.length > 200) {
        error = 'Enter a topic between 2 and 200 characters.';
        notifyListeners();
        return;
      }
    }
    final generation = ++_generation;
    loading = true;
    searched = true;
    error = null;
    notifyListeners();
    try {
      final page = await api.search(query, sort, more ? cursor : null);
      if (_disposed || generation != _generation) return;
      final urls = items.map((s) => s.item.url).toSet();
      items = [...items, ...page.items.where((s) => urls.add(s.item.url))];
      total = page.total;
      cursor = page.nextCursor;
      coverage = page.coverage;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = e is TopicSearchException
          ? e.message
          : 'Search failed. Please retry.';
      restartRequired = e is TopicSearchException && e.restart;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    api.dispose();
    super.dispose();
  }
}
