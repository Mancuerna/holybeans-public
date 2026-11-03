import 'package:holybeans/domain/bean_exchange.dart';

/// Catalog data, separate from the dates, money and stock of one's own bag.
class LoffeeBean {
  const LoffeeBean({
    required this.id,
    required this.card,
    this.description,
    this.roastType,
    this.roastDegree,
    this.roastLevelIsApproximate = false,
    this.elevation,
    this.imageUrl,
    this.harvestNeedsReview = false,
  });

  factory LoffeeBean.fromJson(Map<String, Object?> json) {
    String? text(String field) => switch (json[field]) {
      final String value when value.trim().isNotEmpty => value.trim(),
      final num value => value.toString(),
      _ => null,
    };
    final name = text('roast-name');
    if (name == null) throw const FormatException('Missing coffee name');
    final degree = text('degree');
    final (level, approximate) = _roastLevel(degree);
    int? altitude(String field) {
      final value = num.tryParse(text(field) ?? '');
      if (value == null || !value.isFinite || value <= 0 || value > 9000) {
        return null;
      }
      return value == value.roundToDouble() ? value.toInt() : null;
    }

    final low = altitude('min-elev');
    final high = altitude('max-elev');
    final invalidElevation =
        (text('min-elev') != null && low == null) ||
        (text('max-elev') != null && high == null) ||
        (low != null && high != null && low > high);
    final harvest = text('harvest');
    // Live results contain values such as 46023. They are not harvest years;
    // their date encoding is undocumented, so no calendar date is guessed.
    final harvestNeedsReview =
        harvest != null && RegExp(r'^\d{5,}(?:\.\d+)?$').hasMatch(harvest);
    final origin = SharedOrigin(
      country: text('origin'),
      region: text('region'),
      producer: text('producer'),
      variety: text('variety'),
      process: text('process'),
      harvest: harvestNeedsReview ? null : harvest,
      // A lone endpoint is an exact value; reversed ranges are not guessed.
      altitudeMeters: invalidElevation ? null : low ?? high,
      altitudeMaxMeters:
          !invalidElevation && low != null && high != null && low < high
          ? high
          : null,
    );
    final tasting = json['tasting'];
    final notes = switch (tasting) {
      final List<Object?> values => values.whereType<String>().toList(),
      final String value => value.split(RegExp(r'[,;|]')),
      _ => <String>[],
    };
    return LoffeeBean(
      id: text('id') ?? '',
      card: SharedBean(
        name: name,
        roaster: text('roaster') ?? '',
        roastLevel: level,
        flavorNotes: notes
            .map((n) => n.trim())
            .where((n) => n.isNotEmpty)
            .toList(),
        shopUrl: _httpsLink(text('link')),
        origins: origin.isEmpty ? const [] : [origin],
      ),
      description: text('description'),
      roastType: text('type'),
      roastDegree: degree,
      roastLevelIsApproximate: approximate,
      elevation: invalidElevation
          ? null
          : low != null && high != null
          ? (low == high ? '$low m' : '$low–$high m')
          : low != null
          ? '$low m'
          : high != null
          ? '$high m'
          : null,
      imageUrl: _httpsLink(text('image')),
      harvestNeedsReview: harvestNeedsReview,
    );
  }

  final String id;
  final SharedBean card;
  final String? description;
  final String? roastType;
  final String? roastDegree;
  final bool roastLevelIsApproximate;
  final String? elevation;
  final String? imageUrl;
  final bool harvestNeedsReview;
}

// Equivalences chosen for our five-level scale, not measured roast colours.
// `type` (Filter/Espresso/Omni) never takes part in this conversion.
(String?, bool) _roastLevel(String? degree) {
  final normalized = degree
      ?.toLowerCase()
      .replaceAll(RegExp('[–—]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*-\s*'), '-')
      .trim();
  return switch (normalized) {
    'ultra light' => ('ultra_light', false),
    'light' => ('light', false),
    'medium' => ('medium', false),
    'dark' => ('dark', false),
    'nordic light' => ('ultra_light', true),
    'medium-light' || 'light to medium' => ('omni', true),
    'medium-dark' => ('dark', true),
    'nordic light to light' => ('light', true),
    _ => (null, false),
  };
}

String? _httpsLink(String? value) {
  final uri = Uri.tryParse(value ?? '');
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri.toString()
      : null;
}

/// One page of catalog results. No response modifies the local inventory.
class LoffeePage {
  factory LoffeePage.decode(
    Object? payload, {
    required int page,
    required int limit,
  }) {
    final root = payload is Map<String, Object?>
        ? payload
        : const <String, Object?>{};
    final data = root['data'];
    final nested = data is Map<String, Object?> ? data : root;
    final rows = payload is List<Object?>
        ? payload
        : data is List<Object?>
        ? data
        : nested['beans'] ?? nested['results'];
    if (rows is! List<Object?>) {
      throw const FormatException('Missing coffee results');
    }
    final beans = <LoffeeBean>[];
    for (final row in rows) {
      if (row is! Map<String, Object?>) {
        throw const FormatException('Invalid coffee result');
      }
      beans.add(LoffeeBean.fromJson(row));
    }
    final meta = root['meta'] ?? root['pagination'];
    final metadata = meta is Map<String, Object?> ? meta : root;
    final total = metadata['total'];
    final pages = metadata['totalPages'] ?? metadata['total_pages'];
    final hasMore = switch (metadata['hasMore'] ?? metadata['has_more']) {
      final bool more => more,
      _ when total is num => page * limit < total,
      _ when pages is num => page < pages,
      _ => rows.length == limit,
    };
    return LoffeePage(beans, hasMore: hasMore);
  }
  const LoffeePage(this.beans, {required this.hasMore});
  final List<LoffeeBean> beans;
  final bool hasMore;
}
