/// A web address typed by hand, as a full http(s) URL: trimmed, with
/// `https://` added when no scheme is given. Null for blank input; throws
/// [FormatException] when it cannot be a web page.
String? normalizeWebLink(String? input) {
  final text = input?.trim() ?? '';
  if (text.isEmpty) return null;
  final withScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)
      ? text
      : 'https://$text';
  final uri = Uri.tryParse(withScheme);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      !uri.host.contains('.') ||
      text.contains(' ')) {
    throw FormatException('Not a web address', input);
  }
  return withScheme;
}
