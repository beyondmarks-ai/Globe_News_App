import 'package:firebase_messaging/firebase_messaging.dart';

abstract interface class AlertMessaging {
  Future<bool> allowed({required bool request});
  Future<String?> token();
  Stream<String> get tokenChanges;
}

class FirebaseAlertMessaging implements AlertMessaging {
  @override
  Future<bool> allowed({required bool request}) async {
    final settings =
        await (request
                ? FirebaseMessaging.instance.requestPermission(
                    alert: true,
                    badge: true,
                    sound: true,
                  )
                : FirebaseMessaging.instance.getNotificationSettings())
            .timeout(const Duration(seconds: 30));
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() => FirebaseMessaging.instance.getToken().timeout(
    const Duration(seconds: 15),
  );
  @override
  Stream<String> get tokenChanges => FirebaseMessaging.instance.onTokenRefresh;
}
