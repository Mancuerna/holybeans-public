import 'package:flutter/widgets.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/bean_exchange.dart';

/// The text fields of one origin while its coffee is edited.
class CoffeeOriginDraft {
  CoffeeOriginDraft()
    : componentId = null,
      country = TextEditingController(),
      countryFocus = FocusNode(),
      region = TextEditingController(),
      farm = TextEditingController(),
      producer = TextEditingController(),
      variety = TextEditingController(),
      process = TextEditingController(),
      altitude = TextEditingController(),
      altitudeMax = TextEditingController(),
      harvest = TextEditingController();

  CoffeeOriginDraft.fromComponent(CoffeeComponent component)
    : componentId = component.id,
      country = TextEditingController(text: component.country),
      countryFocus = FocusNode(),
      region = TextEditingController(text: component.region),
      farm = TextEditingController(text: component.farm),
      producer = TextEditingController(text: component.producer),
      variety = TextEditingController(text: component.variety),
      process = TextEditingController(text: component.process),
      altitude = TextEditingController(
        text: component.altitudeMeters?.toString(),
      ),
      altitudeMax = TextEditingController(
        text: component.altitudeMaxMeters?.toString(),
      ),
      harvest = TextEditingController(text: component.harvest);

  /// An origin from a coffee card, for a coffee not saved yet.
  CoffeeOriginDraft.fromCard(SharedOrigin origin)
    : componentId = null,
      country = TextEditingController(text: origin.country),
      countryFocus = FocusNode(),
      region = TextEditingController(text: origin.region),
      farm = TextEditingController(text: origin.farm),
      producer = TextEditingController(text: origin.producer),
      variety = TextEditingController(text: origin.variety),
      process = TextEditingController(text: origin.process),
      altitude = TextEditingController(text: origin.altitudeMeters?.toString()),
      altitudeMax = TextEditingController(
        text: origin.altitudeMaxMeters?.toString(),
      ),
      harvest = TextEditingController(text: origin.harvest);

  final String? componentId;
  final Key key = UniqueKey();
  final TextEditingController country;
  final FocusNode countryFocus;
  final TextEditingController region;
  final TextEditingController farm;
  final TextEditingController producer;
  final TextEditingController variety;
  final TextEditingController process;
  final TextEditingController altitude;
  final TextEditingController altitudeMax;
  final TextEditingController harvest;

  bool get isBlank => [
    country,
    region,
    farm,
    producer,
    variety,
    process,
    altitude,
    altitudeMax,
    harvest,
  ].every((controller) => controller.text.trim().isEmpty);

  void dispose() {
    country.dispose();
    countryFocus.dispose();
    region.dispose();
    farm.dispose();
    producer.dispose();
    variety.dispose();
    process.dispose();
    altitude.dispose();
    altitudeMax.dispose();
    harvest.dispose();
  }
}
