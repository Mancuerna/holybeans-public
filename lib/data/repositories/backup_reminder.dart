import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/backup_reminder.dart';

export 'package:holybeans/domain/backup_reminder.dart';

DateTime? journalFirstUse(List<Coffee> coffees, List<Brew> brews) =>
    firstJournalUse([
      for (final coffee in coffees) coffee.createdAtMs,
      for (final brew in brews) brew.createdAtMs,
    ]);
