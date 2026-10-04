import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'alert_messaging.dart';
import 'news_alert.dart';
import 'news_alert_api.dart';

class NewsAlertController extends ChangeNotifier {
  NewsAlertController({
    required NewsAlertApi api,
    this.userId,
    AlertMessaging? messaging,
  }) : _api = api,
       _messaging = messaging ?? FirebaseAlertMessaging();
  static const _legacyKey = 'news_alert_v1';
  static const _installationKey = 'news_alert_installation_id';
  static const _secretKey = 'news_alert_device_secret';
  String get _alertKey =>
      userId == null ? _legacyKey : 'news_alert_user_$userId';
  final String? userId;
  final NewsAlertApi _api;
  final AlertMessaging _messaging;
  NewsAlert? _alert;
  String? _error;
  bool _busy = false;
  bool _disposed = false;
  bool _suspended = false;
  bool _registered = false;
  StreamSubscription<String>? _tokenSubscription;
  NewsAlert? get alert => _alert;
  String? get error => _error;
  bool get busy => _busy;
  bool get notificationsEnabled => _registered && !_suspended;
  String? lastTestId;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    // Do not inherit an anonymous user's notification area.
    if (userId != null && preferences.containsKey(_legacyKey)) {
      await _unregister();
      await preferences.remove(_legacyKey);
    }
    final encoded = preferences.getString(_alertKey);
    if (encoded != null) {
      try {
        _alert = NewsAlert.tryParse(jsonDecode(encoded));
      } catch (_) {
        _alert = null;
      }
    }
    if (_disposed) return;
    _tokenSubscription ??= _messaging.tokenChanges.listen(_refreshToken);
    // Saved news preferences can open immediately while delivery reconnects.
    if (_alert?.enabled == true) unawaited(_restoreRegistration());
    if (!_disposed) notifyListeners();
  }

  Future<void> _restoreRegistration() async {
    if (_busy || _disposed || _suspended || _alert?.enabled != true) return;
    _setBusy(true);
    try {
      await _register(_alert!, requestPermission: false);
      _registered = true;
      _error = null;
    } catch (_) {
      _registered = false;
      _error =
          'Your area is saved, but alerts could not reconnect. Open news preferences to retry.';
    } finally {
      _setBusy(false);
    }
  }

  Future<void> reconnect() async {
    if (!_registered) await _restoreRegistration();
  }

  Future<bool> save(NewsAlert alert) => _save(alert, enable: true);
  Future<bool> saveWithoutNotifications(NewsAlert alert) =>
      _save(alert, enable: false);

  Future<bool> _save(NewsAlert alert, {required bool enable}) async {
    if (_disposed || _busy || _suspended) return false;
    _setBusy(true);
    try {
      final selected = alert.withEnabled(enable);
      if (enable) {
        await _register(selected, requestPermission: true);
      } else if (_alert?.enabled == true || _registered) {
        await _unregister();
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_alertKey, jsonEncode(selected.toJson()));
      if (_disposed) return false;
      _alert = selected;
      _registered = enable;
      _error = null;
      return true;
    } catch (error) {
      if (!_disposed) {
        _error = error is NewsAlertApiException
            ? error.message
            : 'Unable to save your notification settings. Check your connection and try again.';
      }
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _register(
    NewsAlert alert, {
    required bool requestPermission,
    String? token,
  }) async {
    if (!await _messaging.allowed(request: requestPermission)) {
      throw const NewsAlertApiException(
        'Allow notifications in Android settings, or save your area without alerts.',
      );
    }
    token ??= await _messaging.token();
    if (token == null || token.isEmpty) {
      throw const NewsAlertApiException(
        'This device could not register for notifications. Please try again.',
      );
    }
    final identity = await _identity();
    await _api.save(
      alert: alert,
      installationId: identity.$1,
      deviceSecret: identity.$2,
      fcmToken: token,
    );
  }

  Future<void> _unregister() async {
    final identity = await _identity();
    await _api.disable(installationId: identity.$1, deviceSecret: identity.$2);
  }

  Future<bool> disable() async {
    final selected = _alert;
    return selected == null ? true : saveWithoutNotifications(selected);
  }

  Future<bool> sendTest() async {
    if (_disposed || _busy || !notificationsEnabled) return false;
    _setBusy(true);
    try {
      final identity = await _identity();
      lastTestId = await _api.sendTest(
        installationId: identity.$1,
        deviceSecret: identity.$2,
      );
      _error = null;
      return true;
    } catch (error) {
      _error = error is NewsAlertApiException
          ? error.message
          : 'Test notification timed out. Please retry.';
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Keep account preferences but stop delivery on this device before signing out.
  Future<bool> suspendForSignOut() async {
    if (_disposed || _busy) return false;
    _suspended = true;
    _setBusy(true);
    try {
      if (_alert?.enabled == true || _registered) await _unregister();
      _registered = false;
      _error = null;
      return true;
    } catch (_) {
      _suspended = false;
      _error =
          'Could not stop this device’s alerts. Check your connection, then sign out again.';
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> resumeAfterFailedSignOut() async {
    _suspended = false;
    await _restoreRegistration();
  }

  Future<void> _refreshToken(String token) async {
    if (_disposed || _suspended || _busy || _alert?.enabled != true) return;
    _setBusy(true);
    try {
      await _register(_alert!, requestPermission: false, token: token);
      _registered = true;
      _error = null;
    } catch (_) {
      _registered = false;
      _error = 'Notification registration needs a retry in news preferences.';
    } finally {
      _setBusy(false);
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
