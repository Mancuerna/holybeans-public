import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';

String stockAdjustmentReason(AppLocalizations s, String reason) =>
    switch (reason) {
      'gift' => s.stockAdjustGift,
      'waste' => s.stockAdjustWaste,
      _ => s.stockAdjustCorrection,
    };

String stockAdjustmentError(AppLocalizations s, Object error) =>
    switch (error) {
      StockAdjustmentException(code: 'invalid') => s.stockAdjustInvalid,
      StockAdjustmentException(code: 'insufficient') =>
        s.stockAdjustInsufficient,
      StockAdjustmentException(code: 'unknown') => s.stockAdjustUnknown,
      StockAdjustmentException(code: 'archived') => s.stockAdjustArchived,
      StockAdjustmentException(code: 'capacity') => s.stockAdjustCapacity,
      StockAdjustmentException() => s.stockAdjustChanged,
      _ => s.saveFailed,
    };
