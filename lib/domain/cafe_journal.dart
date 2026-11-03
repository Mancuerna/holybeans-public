/// Editable venue information. A catalog suggestion is copied only on save.
class CafeInput {
  const CafeInput({
    this.id,
    required this.name,
    this.country,
    this.city,
    this.address,
    this.latitude,
    this.longitude,
    this.sourceKey,
    this.sourceUrl,
  });
  final String? id;
  final String name;
  final String? country;
  final String? city;
  final String? address;
  final String? sourceKey;
  final String? sourceUrl;
  final double? latitude;
  final double? longitude;

  void validate() {
    if (name.trim().isEmpty || name.length > 200) {
      throw const FormatException('Invalid cafe name');
    }
    if ((latitude == null) != (longitude == null) ||
        (latitude != null && (!latitude!.isFinite || latitude!.abs() > 90)) ||
        (longitude != null &&
            (!longitude!.isFinite || longitude!.abs() > 180))) {
      throw const FormatException('Invalid cafe location');
    }
  }
}

class CafeDrinkInput {
  const CafeDrinkInput({
    this.id,
    required this.cafe,
    required this.drinkType,
    required this.drankAt,
    this.roaster,
    this.coffeeName,
    this.originCountry,
    this.process,
    this.variety,
    this.notes,
    this.rating,
    this.priceCents,
    this.currency = 'EUR',
    this.photos = const [],
  });
  final String? id;
  final CafeInput cafe;
  final String drinkType;
  final DateTime drankAt;
  final String? roaster;
  final String? coffeeName;
  final String? originCountry;
  final String? process;
  final String? variety;
  final String? notes;
  final double? rating;
  final int? priceCents;
  final String currency;
  final List<String> photos;

  void validate() {
    cafe.validate();
    if (drinkType.trim().isEmpty ||
        drinkType.length > 120 ||
        (roaster?.length ?? 0) > 200 ||
        (rating != null &&
            (!rating!.isFinite || rating! < 0 || rating! > 10)) ||
        (priceCents != null && priceCents! < 0) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const FormatException('Invalid cafe drink');
    }
  }
}
