import 'dart:convert';

import 'package:holybeans/domain/share_template.dart';

const shareTemplateFormat = 'holybeans-share-template';
const maxShareTemplateBytes = 64 * 1024;

// No local ID, default selection or resolved brew values leave the device.
String encodeShareTemplate(ShareTemplate template) {
  template.validate();
  return const JsonEncoder.withIndent('  ').convert({
    'format': shareTemplateFormat,
    'version': 1,
    'name': template.name,
    'style': template.style.name,
    'body': template.body,
  });
}

bool isShareTemplateFile(String source) {
  try {
    final value = jsonDecode(source);
    return value is Map && value['format'] == shareTemplateFormat;
  } on FormatException {
    return false;
  }
}

ShareTemplate decodeShareTemplate(String source, {required String newId}) {
  if (utf8.encode(source).length > maxShareTemplateBytes) {
    throw const FormatException('Share template too large');
  }
  final Object? value = jsonDecode(source);
  if (value is! Map<String, dynamic> ||
      value['format'] != shareTemplateFormat ||
      value['version'] != 1 ||
      value['name'] is! String ||
      value['body'] is! String ||
      !ShareTemplateStyle.values.any((s) => s.name == value['style'])) {
    throw const FormatException('Unsupported share template');
  }
  final template = ShareTemplate(
    id: newId,
    name: (value['name'] as String).trim(),
    style: ShareTemplateStyle.values.byName(value['style'] as String),
    body: value['body'] as String,
  );
  template.validate();
  return template;
}
