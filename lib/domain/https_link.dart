/// An absolute HTTPS link without embedded credentials, or null.
String? httpsLink(String? value) {
  final uri = Uri.tryParse(value ?? '');
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri.toString()
      : null;
}
