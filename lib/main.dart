import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app_intro.dart';
import 'globe_widget.dart';

const mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (mapboxAccessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(mapboxAccessToken);
  }
  runApp(const GlobeNewsApp());
}

class GlobeNewsApp extends StatelessWidget {
  const GlobeNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Globe News',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF2563EB),
        scaffoldBackgroundColor: const Color(0xFF030712),
      ),
      home: const _GlobeHome(),
    );
  }
}

class _GlobeHome extends StatefulWidget {
  const _GlobeHome();

  @override
  State<_GlobeHome> createState() => _GlobeHomeState();
}

class _GlobeHomeState extends State<_GlobeHome> {
  bool _introFinished = false;

  void _finishIntro() {
    if (mounted && !_introFinished) setState(() => _introFinished = true);
  }

  @override
  Widget build(BuildContext context) {
    if (mapboxAccessToken.isEmpty) {
      return const _MissingTokenScreen();
    }
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          GlobeWidget(rotationSuspended: !_introFinished),
          if (!_introFinished) AppIntroOverlay(onFinished: _finishIntro),
        ],
      ),
    );
  }
}

class _MissingTokenScreen extends StatelessWidget {
  const _MissingTokenScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.public_off, size: 52, color: Color(0xFF93C5FD)),
                SizedBox(height: 18),
                Text(
                  'Mapbox access token required',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 10),
                SelectableText(
                  'Run with:\n'
                  'flutter run '
                  '--dart-define=MAPBOX_ACCESS_TOKEN=YOUR_TOKEN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
