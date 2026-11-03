/// The deliberately small formatting vocabulary used by share templates.
class ShareTextRun {
  const ShareTextRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.quote = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;
  final bool quote;
}

class ShareMarkdown {
  static final _punctuation = RegExp(r'[\\*_~`>+\-]');
  static final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);

  // Values are literal data, even when they contain formatting characters.
  static String escape(String value) =>
      value.replaceAllMapped(_punctuation, (m) => '\\${m[0]}');

  static List<ShareTextRun> parse(String source) {
    final result = <ShareTextRun>[];
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) result.add(const ShareTextRun('\n'));
      var line = lines[i];
      final quote = line.startsWith('> ');
      if (quote) {
        result.add(const ShareTextRun('│ ', quote: true));
        line = line.substring(2);
      }
      final bullet = RegExp(r'^(\s*)[-+*] ').firstMatch(line);
      if (bullet != null) {
        result.add(ShareTextRun('${bullet[1]}• ', quote: quote));
        line = line.substring(bullet.end);
      }
      result.addAll(_inline(line, quote: quote));
    }
    return result;
  }

  static List<ShareTextRun> _inline(
    String source, {
    bool bold = false,
    bool italic = false,
    bool strike = false,
    bool quote = false,
    int depth = 0,
  }) {
    final result = <ShareTextRun>[];
    var plain = StringBuffer();
    void flush() {
      if (plain.isEmpty) return;
      result.add(
        ShareTextRun(
          plain.toString(),
          bold: bold,
          italic: italic,
          strike: strike,
          quote: quote,
        ),
      );
      plain = StringBuffer();
    }

    for (var i = 0; i < source.length;) {
      if (source[i] == '\\' &&
          i + 1 < source.length &&
          _punctuation.hasMatch(source[i + 1])) {
        plain.write(source[i + 1]);
        i += 2;
        continue;
      }
      String? marker;
      var end = -1;
      if (depth < 16) {
        for (final candidate in [
          '***',
          '___',
          '**',
          '__',
          '~~',
          '`',
          '*',
          '_',
        ]) {
          if (!source.startsWith(candidate, i)) continue;
          final start = i + candidate.length;
          if (start == source.length || source[start].trim().isEmpty) continue;
          if (candidate.contains('_') &&
              i > 0 &&
              _word.hasMatch(source[i - 1])) {
            continue;
          }
          var search = start;
          while (search < source.length) {
            var found = source.indexOf(candidate, search);
            if (found < 0) break;
            var slashes = 0;
            for (var k = found - 1; k >= 0 && source[k] == '\\'; k--) {
              slashes++;
            }
            if (slashes.isEven &&
                (candidate[0] == '*' || candidate[0] == '_')) {
              var runEnd = found + candidate.length;
              while (runEnd < source.length && source[runEnd] == candidate[0]) {
                runEnd++;
              }
              if (candidate.length == 1 && runEnd - found == 2) {
                search = runEnd;
                continue;
              }
              found = runEnd - candidate.length;
            }
            final after = found + candidate.length;
            if (found > start &&
                slashes.isEven &&
                source[found - 1].trim().isNotEmpty &&
                !(candidate.contains('_') &&
                    after < source.length &&
                    _word.hasMatch(source[after]))) {
              end = found;
              marker = candidate;
              break;
            }
            search = found + 1;
          }
          if (marker != null) break;
        }
      }
      if (marker == null) {
        plain.write(source[i++]);
        continue;
      }
      flush();
      final content = source.substring(i + marker.length, end);
      if (marker == '`') {
        result.add(
          ShareTextRun(
            content.replaceAllMapped(RegExp(r'\\([\\*_~`>+\-])'), (m) => m[1]!),
            bold: bold,
            italic: italic,
            strike: strike,
            code: true,
            quote: quote,
          ),
        );
      } else {
        result.addAll(
          _inline(
            content,
            bold:
                bold || marker == '**' || marker == '__' || marker.length == 3,
            italic:
                italic || marker == '*' || marker == '_' || marker.length == 3,
            strike: strike || marker == '~~',
            quote: quote,
            depth: depth + 1,
          ),
        );
      }
      i = end + marker.length;
    }
    flush();
    return result;
  }
}
