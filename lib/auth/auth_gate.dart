import 'package:flutter/material.dart';
import '../notifications/news_alert_api.dart';
import '../notifications/news_alert_controller.dart';
import '../notifications/news_alert_sheet.dart';
import '../notifications/news_notification_service.dart';
import 'auth_client.dart';
import 'auth_screen.dart';

typedef SignedInBuilder =
    Widget Function(BuildContext, NewsAlertController, VoidCallback);

class AuthGate extends StatefulWidget {
  const AuthGate({
    required this.client,
    required this.apiBaseUrl,
    required this.mapboxToken,
    required this.builder,
    super.key,
  });
  final AuthClient client;
  final String apiBaseUrl;
  final String mapboxToken;
  final SignedInBuilder builder;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<NewsAccount?> _accounts = widget.client.accounts;
  @override
  Widget build(BuildContext context) => StreamBuilder<NewsAccount?>(
    stream: _accounts,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Scaffold(
          body: Center(
            child: Text('Account connection failed. Please reopen the app.'),
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final account = snapshot.data;
      if (account == null) return AuthScreen(client: widget.client);
      return _AccountSession(
        key: ValueKey(account.id),
        account: account,
        client: widget.client,
        apiBaseUrl: widget.apiBaseUrl,
        mapboxToken: widget.mapboxToken,
        builder: widget.builder,
      );
    },
  );
}

class _AccountSession extends StatefulWidget {
  const _AccountSession({
    required this.account,
    required this.client,
    required this.apiBaseUrl,
    required this.mapboxToken,
    required this.builder,
    super.key,
  });
  final NewsAccount account;
  final AuthClient client;
  final String apiBaseUrl;
  final String mapboxToken;
  final SignedInBuilder builder;
  @override
  State<_AccountSession> createState() => _AccountSessionState();
}

class _AccountSessionState extends State<_AccountSession> {
  late final NewsAlertController _alerts;
  bool _loading = true;
  bool _signingOut = false;
  String? _loadError;
  @override
  void initState() {
    super.initState();
    _alerts = NewsAlertController(
      userId: widget.account.id,
      api: NewsAlertApi(baseUrl: widget.apiBaseUrl),
    )..addListener(_changed);
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _alerts.load();
    } catch (_) {
      if (mounted) {
        _loadError =
            'Could not load your news preferences. Check your connection and retry.';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseArea() async {
    _alerts.clearError();
    await showNewsAlertSheet(
      context: context,
      controller: _alerts,
      mapboxAccessToken: widget.mapboxToken,
    );
  }

  Future<void> _signOut() async {
    if (_signingOut || _alerts.busy) return;
    setState(() => _signingOut = true);
    try {
      if (!await _alerts.suspendForSignOut()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_alerts.error ?? 'Please retry signing out.'),
            ),
          );
        }
        return;
      }
      await widget.client.signOut();
    } catch (error) {
      await _alerts.resumeAfterFailedSignOut();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _showAccount() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Your account',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(widget.account.email),
              const SizedBox(height: 24),
              Text(
                _alerts.alert?.locationLabel ?? 'Choose your news area',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              if (_alerts.alert case final alert?)
                Text(
                  alert.usesCustomRadius
                      ? 'Within ${alert.radiusMeters ~/ 1000} km'
                      : 'Whole city / state area',
                ),
              const SizedBox(height: 8),
              Text(
                _alerts.notificationsEnabled
                    ? 'Area alerts registered. Send a test to verify delivery.'
                    : 'Area notifications are off or need reconnecting',
              ),
              if (_alerts.error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    style: const TextStyle(color: Color(0xFFFCA5A5)),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, 'area'),
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Change news area and radius'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _alerts.notificationsEnabled && !_alerts.busy
                    ? () => Navigator.pop(context, 'test')
                    : null,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Send test notification'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _signingOut || _alerts.busy
                    ? null
                    : () => Navigator.pop(context, 'signout'),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your area preferences are saved for this account on this device.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'area') await _chooseArea();
    if (action == 'signout') await _signOut();
    if (action == 'test') {
      final sent = await _alerts.sendTest();
      if (!mounted) return;
      final receivedId = NewsNotificationService.instance.lastTestId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? receivedId != null && receivedId == _alerts.lastTestId
                      ? 'Test received on this device. Push delivery verified.'
                      : 'Test accepted by Firebase. Delivery is verified only when it appears on this device.'
                : _alerts.error ?? 'Test notification could not be sent.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!),
                const SizedBox(height: 20),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }
    if (_alerts.alert != null) {
      return widget.builder(context, _alerts, _showAccount);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your news preferences'),
        actions: [
          TextButton(
            onPressed: _signingOut ? null : _signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.travel_explore,
                    size: 72,
                    color: Color(0xFF93C5FD),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Where should your news come from?',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Signed in as ${widget.account.email}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Search for your city, district, or state. Follow the whole area, or choose a radius from 2 to 250 km. You can change this later.',
                    style: TextStyle(height: 1.6),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    key: const Key('onboarding-area'),
                    onPressed: _signingOut ? null : _chooseArea,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    icon: const Icon(Icons.location_on_outlined),
                    label: const Text('Choose city / state and radius'),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Enable notifications to receive news matching your area. You can also save your area with notifications off.',
                    style: TextStyle(color: Colors.white60, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _alerts.removeListener(_changed);
    _alerts.dispose();
    super.dispose();
  }
}
