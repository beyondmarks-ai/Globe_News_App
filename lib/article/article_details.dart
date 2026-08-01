class ArticleDetails {
  const ArticleDetails({
    required this.title,
    required this.emoji,
    required this.whatHappened,
    required this.when,
    required this.where,
    required this.why,
    required this.how,
    this.imageUrl,
  });

  final String title;
  final String emoji;
  final String whatHappened;
  final String when;
  final String where;
  final String why;
  final String how;
  final String? imageUrl;

  Uri? get imageUri => validatedHttpUri(imageUrl);

  factory ArticleDetails.fromJson(Map<String, Object?> json) {
    final image = _text(json['imageUrl']);
    return ArticleDetails(
      title: _text(json['title']),
      emoji: _text(json['emoji']),
      whatHappened: _text(json['whatHappened']),
      when: _text(json['when']),
      where: _text(json['where']),
      why: _text(json['why']),
      how: _text(json['how']),
      imageUrl: validatedHttpUri(image) == null ? null : image,
    );
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';
}

Uri? validatedHttpUri(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.scheme.toLowerCase() != 'http' &&
          uri.scheme.toLowerCase() != 'https')) {
    return null;
  }
  return uri;
}
