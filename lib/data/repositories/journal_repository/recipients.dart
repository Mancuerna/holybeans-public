part of '../journal_repository.dart';

extension RecipientOperations on JournalRepository {
  Stream<List<Recipient>> watchRecipients({bool includeArchived = false}) =>
      recipients.watchRecipients(includeArchived: includeArchived);
  Future<Recipient> saveRecipient({
    String? id,
    required String name,
    required double emptyGrams,
    bool isPortafilter = false,
  }) => recipients.saveRecipient(
    id: id,
    name: name,
    emptyGrams: emptyGrams,
    isPortafilter: isPortafilter,
  );
  Future<void> setRecipientArchived(String id, {required bool archived}) =>
      recipients.setRecipientArchived(id, archived: archived);
  Future<Recipient?> _recipient(String? id) => recipients.requireRecipient(id);
}
