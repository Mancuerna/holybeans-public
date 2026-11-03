import 'package:holybeans/domain/label_graphic.dart';
import 'package:holybeans/domain/label_image_options.dart';
import 'package:holybeans/domain/share_template.dart';

export 'package:holybeans/domain/label_image_options.dart';
export 'package:holybeans/domain/label_printer_profile.dart';

enum LabelKind { coffee, frozen }

const coffeeLabelTags = {
  'coffee',
  'roaster',
  'country',
  'region',
  'variety',
  'process',
  'farm',
  'producer',
  'flavor_notes',
  'roast_date',
};
const frozenLabelTags = {
  ...coffeeLabelTags,
  'freeze_date',
  'portion_weight',
  'portion_label',
};

class LabelTemplate {
  const LabelTemplate({
    required this.id,
    required this.name,
    required this.kind,
    required this.body,
    this.imagePng,
    this.imageOptions,
  });

  final String id;
  final String name;
  final LabelKind kind;
  final String body;
  final String? imagePng;
  final LabelImageOptions? imageOptions;
  LabelImageOptions get effectiveImageOptions =>
      imageOptions ?? LabelImageOptions(size: body.trim().isEmpty ? 1 : 0.4);

  Set<String> get allowedTags =>
      kind == LabelKind.coffee ? coffeeLabelTags : frozenLabelTags;

  void validate() {
    if (id.isEmpty ||
        name.trim().isEmpty ||
        name.length > 80 ||
        (body.trim().isEmpty && imagePng == null) ||
        body.length > 8000 ||
        TemplateEngine.unknownTags(body, allowedTags: allowedTags).isNotEmpty) {
      throw const FormatException('Invalid label template');
    }
    if (imagePng != null) LabelGraphic.bytes(imagePng!);
    effectiveImageOptions.validate();
  }

  String render(Map<String, String> values) =>
      TemplateEngine.renderMarkdown(body, values, allowedTags: allowedTags);

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'body': body,
    'imagePng': ?imagePng,
    'imageOptions': ?imageOptions?.toJson(),
  };

  static LabelTemplate fromJson(Map<String, dynamic> json) {
    final result = LabelTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: LabelKind.values.byName(json['kind'] as String),
      body: json['body'] as String,
      imagePng: json['imagePng'] as String?,
      imageOptions: json['imageOptions'] == null
          ? null
          : LabelImageOptions.fromJson(
              json['imageOptions'] as Map<String, dynamic>,
            ),
    );
    result.validate();
    return result;
  }
}
