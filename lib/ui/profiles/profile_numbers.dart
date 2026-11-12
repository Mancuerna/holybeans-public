import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

NumberFormat profileNumber(BuildContext context, {int decimals = 1}) =>
    NumberFormat(
      '0.${'#' * decimals}',
      Localizations.localeOf(context).toString(),
    );

String profileInput(BuildContext context, double value) => value
    .toString()
    .replaceFirst(RegExp(r'\.0$'), '')
    .replaceAll('.', profileNumber(context).symbols.DECIMAL_SEP);
