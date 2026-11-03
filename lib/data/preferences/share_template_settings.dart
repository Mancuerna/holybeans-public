import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/preferences_row.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/domain/share_template.dart';

class ShareConfiguration {
  ShareConfiguration({
    required this.fields,
    this.templates = const [],
    this.defaults = const {},
    this.labelTemplates = const [],
  });

  final Set<BrewParameter> fields;
  final List<ShareTemplate> templates;
  final Map<ShareTemplateStyle, String> defaults;
  final List<LabelTemplate> labelTemplates;

  ShareTemplate? selected(ShareTemplateStyle style) => templates
      .where((t) => t.style == style && t.id == defaults[style])
      .firstOrNull;

  Map<String, Object> toJson() => {
    'version': 1,
    'fields': encodeSharedParameters(fields),
    'templates': [for (final template in templates) template.toJson()],
    'defaults': {for (final e in defaults.entries) e.key.name: e.value},
    if (labelTemplates.isNotEmpty)
      'labelTemplates': [for (final t in labelTemplates) t.toJson()],
  };

  static ShareConfiguration decode(String? source) {
    if (source == null) {
      return ShareConfiguration(fields: {...defaultSharedParameters});
    }
    final Object? decoded = jsonDecode(source);
    if (decoded is List) {
      return ShareConfiguration(
        fields: decodeSharedParameters(decoded.whereType<String>().toList()),
      );
    }
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('Unsupported share preferences');
    }
    final templates = [
      for (final item in decoded['templates'] as List)
        ShareTemplate.fromJson(item as Map<String, dynamic>),
    ];
    for (final template in templates) {
      template.validate();
    }
    return ShareConfiguration(
      fields: decodeSharedParameters(
        (decoded['fields'] as List).cast<String>(),
      ),
      templates: templates,
      labelTemplates: [
        for (final item in (decoded['labelTemplates'] as List? ?? const []))
          LabelTemplate.fromJson(item as Map<String, dynamic>),
      ],
      defaults: {
        for (final e in (decoded['defaults'] as Map<String, dynamic>).entries)
          ShareTemplateStyle.values.byName(e.key): e.value as String,
      },
    );
  }
}

class ShareTemplateSettings {
  ShareTemplateSettings(this.database);

  final AppDatabase database;

  Future<ShareConfiguration> load() async => ShareConfiguration.decode(
    (await database.loadPreferences())?.shareFieldsJson,
  );

  Future<void> _update(
    ShareConfiguration Function(ShareConfiguration) change,
  ) => database.writeGate.withPreferencesLock(
    () => database.transaction(() async {
      final next = change(await load());
      await database.savePreferences(
        AppPreferencesCompanion(
          shareFieldsJson: Value(jsonEncode(next.toJson())),
        ),
      );
    }),
  );

  Future<void> saveLabelTemplate(LabelTemplate template) {
    template.validate();
    return _update(
      (old) => ShareConfiguration(
        fields: old.fields,
        templates: old.templates,
        defaults: old.defaults,
        labelTemplates: [
          for (final previous in old.labelTemplates)
            if (previous.id != template.id) previous,
          template,
        ],
      ),
    );
  }

  Future<void> deleteLabelTemplate(String id) => _update(
    (old) => ShareConfiguration(
      fields: old.fields,
      templates: old.templates,
      defaults: old.defaults,
      labelTemplates: old.labelTemplates.where((t) => t.id != id).toList(),
    ),
  );

  Future<void> saveFields(Set<BrewParameter> fields) {
    if (!fields.any((field) => field.canShare)) {
      throw ArgumentError.value(fields);
    }
    return _update(
      (old) => ShareConfiguration(
        fields: fields,
        labelTemplates: old.labelTemplates,
        templates: old.templates,
        defaults: old.defaults,
      ),
    );
  }

  Future<void> saveTemplate(ShareTemplate template) {
    template.validate();
    return _update(
      (old) => ShareConfiguration(
        fields: old.fields,
        labelTemplates: old.labelTemplates,
        templates: [
          for (final previous in old.templates)
            if (previous.id != template.id) previous,
          template,
        ],
        defaults: {
          for (final e in old.defaults.entries)
            if (e.value != template.id || e.key == template.style)
              e.key: e.value,
        },
      ),
    );
  }

  Future<void> deleteTemplate(String id) => _update(
    (old) => ShareConfiguration(
      fields: old.fields,
      labelTemplates: old.labelTemplates,
      templates: old.templates.where((t) => t.id != id).toList(),
      defaults: {
        for (final e in old.defaults.entries)
          if (e.value != id) e.key: e.value,
      },
    ),
  );

  Future<void> select(ShareTemplateStyle style, String? id) => _update((old) {
    if (id != null &&
        !old.templates.any((t) => t.id == id && t.style == style)) {
      throw ArgumentError.value(id);
    }
    return ShareConfiguration(
      fields: old.fields,
      labelTemplates: old.labelTemplates,
      templates: old.templates,
      defaults: {...old.defaults}
        ..remove(style)
        ..addAll({style: ?id}),
    );
  });
}
