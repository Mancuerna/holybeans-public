/// The recipient and tare actually chosen for one preparation.
class RecipientSnapshot {
  const RecipientSnapshot({
    required this.id,
    required this.name,
    required this.grams,
  });
  final String id;
  final String name;
  final double grams;

  void validate() {
    if (id.isEmpty ||
        name.trim().isEmpty ||
        name.length > 120 ||
        !grams.isFinite ||
        grams <= 0 ||
        grams > 10000) {
      throw ArgumentError('Invalid recipient');
    }
  }
}
