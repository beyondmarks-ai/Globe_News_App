class TalkNewsSession {
  const TalkNewsSession({required this.token, required this.webrtcUri});

  final String token;
  final Uri webrtcUri;

  factory TalkNewsSession.fromJson(Map<String, Object?> json) {
    final token = json['token']?.toString().trim() ?? '';
    final uri = Uri.tryParse(json['webrtcUrl']?.toString().trim() ?? '');
    if (token.isEmpty ||
        uri == null ||
        uri.scheme != 'https' ||
        !uri.host.endsWith('.openai.azure.com')) {
      throw const FormatException('Invalid realtime session');
    }
    return TalkNewsSession(token: token, webrtcUri: uri);
  }
}
