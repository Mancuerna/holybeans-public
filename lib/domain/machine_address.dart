Uri gaggimateAddress(String address) {
  final text = address.trim();
  if (text.isEmpty) throw const FormatException('Empty address');
  final uri = Uri.parse(text.contains('://') ? text : 'http://$text');
  if (uri.host.isEmpty ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException('Invalid machine address');
  }
  return Uri(scheme: uri.scheme, host: uri.host.toLowerCase(), port: uri.port);
}

Uri meticulousAddress(String address) {
  final text = address.trim();
  if (text.isEmpty) throw const FormatException('Empty address');
  final uri = Uri.parse(text.contains('://') ? text : 'http://$text');
  if (uri.host.isEmpty || !{'http', 'https'}.contains(uri.scheme)) {
    throw FormatException('Invalid address', address);
  }
  return Uri(scheme: uri.scheme, host: uri.host, port: uri.port);
}
