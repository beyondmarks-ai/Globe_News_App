class TalkNewsLanguage {
  const TalkNewsLanguage._(this.code, this.label);

  final String code;
  final String label;

  static const auto = TalkNewsLanguage._('auto', 'Auto detect');
  static const english = TalkNewsLanguage._('en-US', 'English');
  static const kannada = TalkNewsLanguage._('kn-IN', 'ಕನ್ನಡ');
  static const hindi = TalkNewsLanguage._('hi-IN', 'हिन्दी');
  static const urdu = TalkNewsLanguage._('ur-PK', 'اردو');

  static const values = [auto, english, kannada, hindi, urdu];
}

class TalkNewsVoice {
  const TalkNewsVoice._(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  static const coral = TalkNewsVoice._('coral', 'Coral', 'Warm');
  static const sage = TalkNewsVoice._('sage', 'Sage', 'Calm');
  static const shimmer = TalkNewsVoice._('shimmer', 'Shimmer', 'Bright');
  static const verse = TalkNewsVoice._('verse', 'Verse', 'Clear');
  static const echo = TalkNewsVoice._('echo', 'Echo', 'Deep');

  static const values = [coral, sage, shimmer, verse, echo];
}
