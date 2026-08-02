import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/timeline/timeline_news_item.dart';

void main() {
  Map<String, Object?> base() => {
    'id': 'story-1',
    'place': 'Bidar',
    'country': 'India',
    'lat': 17.9104,
    'lon': 77.5199,
    'tone': -3.2,
    'url': 'https://example.com/article',
    'source': 'News Source',
  };

  test('parses snake_case fields', () {
    final json = base()
      ..addAll({
        'has_embedding': true,
        'ai_ready': true,
        'pulse_strength': 1.2,
      });
    final item = TimelineNewsItem.tryParse(json)!;

    expect(item.hasEmbedding, isTrue);
    expect(item.aiReady, isTrue);
    expect(item.pulseStrength, 1.2);
    expect(item.pulseReady, isTrue);
  });

  test('parses camelCase fields', () {
    final json = base()
      ..addAll({'hasEmbedding': true, 'aiReady': true, 'pulseStrength': 1.4});
    final item = TimelineNewsItem.tryParse(json)!;

    expect(item.hasEmbedding, isTrue);
    expect(item.aiReady, isTrue);
    expect(item.pulseStrength, 1.4);
  });

  test('accepts headline and title variants for grid cards', () {
    expect(
      TimelineNewsItem.tryParse(
        base()..['headline'] = 'Bidar update',
      )!.headline,
      'Bidar update',
    );
    expect(
      TimelineNewsItem.tryParse(base()..['title'] = 'World update')!.headline,
      'World update',
    );
  });

  test('accepts supported boolean representations', () {
    for (final value in [true, 1, 'true', '1']) {
      final item = TimelineNewsItem.tryParse(
        base()..addAll({'has_embedding': value, 'ai_ready': value}),
      )!;
      expect(item.pulseReady, isTrue, reason: '$value should be true');
    }
    for (final value in [false, 0, 'false', '0']) {
      final item = TimelineNewsItem.tryParse(
        base()..addAll({'has_embedding': value, 'ai_ready': value}),
      )!;
      expect(item.pulseReady, isFalse, reason: '$value should be false');
    }
  });

  test('parses numeric strings safely', () {
    final item = TimelineNewsItem.tryParse({
      ...base(),
      'lat': '17.9104',
      'lon': '77.5199',
      'tone': '-3.2',
      'pulse_strength': '1.5',
    })!;

    expect(item.lat, 17.9104);
    expect(item.lon, 77.5199);
    expect(item.tone, -3.2);
    expect(item.pulseStrength, 1.5);
  });

  test('rejects missing and out-of-range coordinates', () {
    expect(TimelineNewsItem.tryParse({...base(), 'lat': 91}), isNull);
    expect(TimelineNewsItem.tryParse({...base(), 'lon': -181}), isNull);
    expect(TimelineNewsItem.tryParse({...base(), 'lat': 'bad'}), isNull);
  });

  test('pulseReady requires embedding and AI readiness', () {
    final item = TimelineNewsItem.tryParse(
      base()..addAll({'has_embedding': true, 'ai_ready': false}),
    )!;
    expect(item.pulseReady, isFalse);
  });

  test('pulseStrength defaults and clamps to safe bounds', () {
    expect(TimelineNewsItem.tryParse(base())!.pulseStrength, 1);
    expect(
      TimelineNewsItem.tryParse(
        base()..['pulse_strength'] = 100,
      )!.pulseStrength,
      TimelineNewsItem.maxPulseStrength,
    );
    expect(
      TimelineNewsItem.tryParse(
        base()..['pulse_strength'] = -10,
      )!.pulseStrength,
      TimelineNewsItem.minPulseStrength,
    );
  });
}
