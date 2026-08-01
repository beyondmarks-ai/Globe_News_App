enum ArticleLanguage {
  english('en-US', 'English', false),
  kannada('kn-IN', '\u0C95\u0CA8\u0CCD\u0CA8\u0CA1', false),
  hindi('hi-IN', '\u0939\u093F\u0928\u094D\u0926\u0940', false),
  urdu('ur-PK', '\u0627\u0631\u062F\u0648', true);

  const ArticleLanguage(this.code, this.label, this.isRtl);

  final String code;
  final String label;
  final bool isRtl;
}
