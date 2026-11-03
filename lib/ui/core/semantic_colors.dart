import 'package:flutter/material.dart';

Color frozenColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF8FB8D8)
    : const Color(0xFF2F5F80);
