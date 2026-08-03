import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'news_alert.dart';
import 'news_alert_api.dart';

class NewsAlertController extends ChangeNotifier {
  NewsAlertController({required NewsAlertApi api}) : _api = api;

  static const _alertKey = 'news_alert_v1';
  static const _installationKey = 'news_alert_installation_id';
  static const _secretKey = 'news_alert_device_secret';

  final NewsAlertApi _api;
  NewsAlert? _alert;
  String? _error;
  bool _busy = false;
  bool _disposed = false;
  StreamSubscription<String>? _tokenSubscription;

  NewsAlert? get alert => _alert;
  String? get error => _error;
  bool get busy => _busy;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_alertKey);
    if (encoded != null) {
      try {
        _alert = NewsAlert.tryParse(jsonDecode(encoded));
      } catch (_) {
        _alert = null;
      }
    }
    if (!_disposed) notifyListeners();
    _tokenSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      _refreshToken,
    );
  }

  Future<bool> save(NewsAlert alert) async {
    if (_disposed || _busy) return false;
    _setBusy(true);
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        throw const NewsAlertApiException(
          'Allow notifications in Android settings to enable area alerts.',
        );
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        throw const NewsAlertApiException(
          'This device could not register for notifications.',
        );
      }
      final identity = await _identity();
      await _api.save(
        alert: alert,
        installationId: identity.$1,
        deviceSecret: identity.$2,
        fcmToken: token,
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_alertKey, jsonEncode(alert.toJson()));
      if (_disposed) return false;
      _alert = alert;
      _error = null;
      return true;
    } catch (error) {
      if (!_disposed) _error = error.toString();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> disable() async {
    if (_disposed || _busy) return false;
    _setBusy(true);
    try {
      final identity = await _identity();
      await _api.disable(
        installationId: identity.$1,
        deviceSecret: identity.$2,
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_alertKey);
      if (_disposed) return false;
      _alert = null;
      _error = null;
      return true;
    } catch (error) {
      if (!_disposed) _error = error.toString();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _refreshToken(String token) async {
    final alert = _alert;
    if (_disposed || alert == null) return;
    try {
      final identity = await _identity();
      await _api.save(
        alert: alert,
        installationId: identity.$1,
        deviceSecret: identity.$2,
        fcmToken: token,
      );
    } catch (_) {
      // The next settings save or token refresh will retry silently.
    }
  }

  Future<(String, String)> _identity() async {
    final preferences = await SharedPreferences.getInstance();
    var installationId = preferences.getString(_installationKey);
    var secret = preferences.getString(_secretKey);
    if (installationId == null || secret == null) {
      final random = Random.secure();
      String value(int bytes) => List.generate(
        bytes,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      installationId ??= value(16);
      secret ??= value(32);
      await preferences.setString(_installationKey, installationId);
      await preferences.setString(_secretKey, secret);
    }
    return (installationId, secret);
  }

  void clearError() {
    if (_error == null || _disposed) return;
    _error = null;
    notifyListeners();
  }

  void _setBusy(bool value) {
    if (_disposed) return;
    _busy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_tokenSubscription?.cancel());
    _api.dispose();
    super.dispose();
  }
}
