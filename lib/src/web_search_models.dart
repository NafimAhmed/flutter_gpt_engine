class WebSource {
  const WebSource({
    required this.title,
    required this.url,
    required this.text,
    this.snippet = '',
    this.provider = 'web',
  });

  final String title;
  final String url;
  final String text;
  final String snippet;
  final String provider;
}

class WebSearchResult {
  const WebSearchResult({
    required this.query,
    required this.sources,
    this.provider = 'web',
  });

  final String query;
  final List<WebSource> sources;
  final String provider;

  bool get isEmpty => sources.isEmpty;
  bool get isNotEmpty => sources.isNotEmpty;

  String toPromptContext({
    int maxCharacters = 9000,
  }) {
    if (sources.isEmpty || maxCharacters <= 0) return '';

    final buffer = StringBuffer();

    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      final snippetPart = source.snippet.trim().isEmpty
          ? ''
          : 'Search snippet: ${source.snippet.trim()}\n';

      final block = '''
[${i + 1}]
Provider: ${source.provider}
Title: ${source.title}
URL: ${source.url}
${snippetPart}Relevant page content:
${source.text}

''';

      final remaining = maxCharacters - buffer.length;
      if (remaining <= 0) break;

      if (block.length <= remaining) {
        buffer.write(block);
      } else {
        buffer.write(block.substring(0, remaining));
        break;
      }
    }

    return buffer.toString().trim();
  }
}
