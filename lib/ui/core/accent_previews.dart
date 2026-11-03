import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/frozen_stock_badge.dart';

@Preview(name: 'Frozen stock · light', size: Size(360, 300))
Widget frozenLightPreview() => _preview(ThemeMode.light);

@Preview(name: 'Frozen stock · dark', size: Size(360, 300))
Widget frozenDarkPreview() => _preview(ThemeMode.dark);

Widget _preview(ThemeMode mode) => MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: mode,
  locale: const Locale('es'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final state in [FrozenStockState.some, FrozenStockState.all])
            Padding(
              padding: const EdgeInsets.all(12),
              child: FrozenStockBadge(state: state),
            ),
        ],
      ),
    ),
  ),
);
