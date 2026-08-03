import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

class NewsNotificationAction {
  const NewsNotificationAction({
    required this.kind,
    this.storyId,
    this.latitude,
    this.longitude,
  });

  final String kind;
  final String? storyId;
  final double? latitude;
  final double? longitude;

  factory NewsNotificationAction.fromMessage(RemoteMessage message) {
    final data = message.data;
    return NewsNotificationAction(
      kind: data['type'] ?? 'group',
      storyId: data['storyId'],
      latitude: double.tryParse(data['lat'] ?? ''),
      longitude: double.tryParse(data['lon'] ?? ''),
    );
  }
}

class NewsNotificationService {
  NewsNotificationService._();
  static final instance = NewsNotificationService._();

  final _openedController =
      StreamController<NewsNotificationAction>.broadcast();
  final _foregroundController = StreamController<RemoteMessage>.broadcast();
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  NewsNotificationAction? _initialAction;

  Stream<NewsNotificationAction> get opened => _openedController.stream;
  Stream<RemoteMessage> get foregroundMessages => _foregroundController.stream;

  Future<void> initialize() async {
    _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
      (message) =>
          _openedController.add(NewsNotificationAction.fromMessage(message)),
    );
    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen(
      _foregroundController.add,
    );
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _initialAction = NewsNotificationAction.fromMessage(initial);
    }
  }

  NewsNotificationAction? takeInitialAction() {
    final action = _initialAction;
    _initialAction = null;
    return action;
  }
}
