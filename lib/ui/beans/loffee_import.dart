import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/loffee_api.dart';
import 'package:holybeans/domain/loffee_bean.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/bean_import.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/beans/loffee_search_page.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';

Future<void> importLoffeeBean(
  BuildContext context,
  JournalActions actions,
  List<Coffee> coffees,
  LoffeeServices services,
) async {
  final bean = await Navigator.of(context).push<LoffeeBean>(
    MaterialPageRoute(builder: (_) => LoffeeSearchPage(services: services)),
  );
  if (bean == null || !context.mounted) return;
  if (!await confirmBeanImport(context, actions, coffees, bean.card)) return;
  if (!context.mounted) return;
  final s = AppLocalizations.of(context)!;
  final notes = [
    s.loffeeAttribution,
    ?bean.description,
    if (bean.roastType case final value?) '${s.loffeeRoastType}: $value',
    if (bean.harvestNeedsReview) s.loffeeHarvestNeedsReview,
  ].join('\n');
  final saved = await showFormSheet<Object>(
    context,
    CoffeeForm(
      repository: actions.repository,
      photos: actions.photos,
      card: bean.card,
      initialNotes: notes,
      roastLevelHint: bean.roastLevelIsApproximate
          ? s.loffeeRoastApproximation(bean.roastDegree!)
          : null,
      importPhoto: bean.imageUrl == null
          ? null
          : () => services.api.photo(bean.imageUrl!),
    ),
  );
  if (saved != null && context.mounted) actions.message(s.beanSaved);
}
