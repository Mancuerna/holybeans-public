import 'package:flutter/material.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/brew_parameter_labels.dart';

/// One list of every brew parameter with two choices: whether it shows in
/// the form, the details and the history, and whether it is shared.
class BrewParametersPage extends StatefulWidget {
  const BrewParametersPage({super.key, required this.settings});

  final BrewParameterSettings settings;

  @override
  State<BrewParametersPage> createState() => _BrewParametersPageState();
}

class _BrewParametersPageState extends State<BrewParametersPage> {
  late Stream<Set<BrewParameter>> _hidden;
  late Stream<Set<BrewParameter>> _shared;

  @override
  void initState() {
    super.initState();
    _watchSettings();
  }

  @override
  void didUpdateWidget(covariant BrewParametersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) _watchSettings();
  }

  void _watchSettings() {
    _hidden = widget.settings.watchHidden();
    _shared = widget.settings.watchShared();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(title: Text(s.brewParameters)),
      body: StreamBuilder<Set<BrewParameter>>(
        stream: _hidden,
        builder: (context, hiddenSnapshot) => StreamBuilder<Set<BrewParameter>>(
          stream: _shared,
          builder: (context, sharedSnapshot) {
            final hidden = hiddenSnapshot.data;
            final shared = sharedSnapshot.data;
            if (hidden == null || shared == null) {
              return const Center(child: CircularProgressIndicator());
            }
            Set<BrewParameter> hideable(Set<BrewParameter> chosen) => {
              for (final parameter in chosen)
                if (parameter.canHide && parameter.isBrewField) parameter,
            };
            final current = hideable(hidden);
            bool same(Set<BrewParameter> preset) =>
                current.length == preset.length && current.containsAll(preset);
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverList.list(
                    children: [
                      Text(s.brewParametersHint),
                      const SizedBox(height: 4),
                      Text(s.brewParametersHiddenNote, style: muted),
                      const SizedBox(height: 12),
                      // Two common choices in one tap; the boxes below stay
                      // for anything in between.
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          ChoiceChip(
                            key: const ValueKey('parameters-preset-all'),
                            label: Text(s.parametersPresetAll),
                            selected: current.isEmpty,
                            onSelected: (_) => widget.settings.saveHidden({}),
                          ),
                          ChoiceChip(
                            key: const ValueKey('parameters-preset-essential'),
                            label: Text(s.parametersPresetEssential),
                            selected: same(essentialHiddenParameters),
                            onSelected: (_) => widget.settings.saveHidden({
                              ...essentialHiddenParameters,
                            }),
                          ),
                        ],
                      ),
                      Text(s.parametersPresetsHint, style: muted),
                    ],
                  ),
                ),
                // Each group keeps its column names in sight while its
                // rows scroll under them.
                for (final group in BrewParameterGroup.values)
                  SliverMainAxisGroup(
                    slivers: [
                      PinnedHeaderSliver(
                        child: ColoredBox(
                          color: theme.colorScheme.surface,
                          child: _GroupHeader(group: group),
                        ),
                      ),
                      SliverList.list(
                        children: [
                          for (final parameter in BrewParameter.values)
                            if (parameter.group == group)
                              _ParameterRow(
                                parameter: parameter,
                                shown: !hidden.contains(parameter),
                                shared: shared.contains(parameter),
                                // At least one parameter must stay shared.
                                canUnshare: shared.length > 1,
                                onShown: (value) => widget.settings.saveHidden(
                                  value
                                      ? ({...hidden}..remove(parameter))
                                      : {...hidden, parameter},
                                ),
                                onShared: (value) => widget.settings.saveShared(
                                  value
                                      ? {...shared, parameter}
                                      : ({...shared}..remove(parameter)),
                                ),
                              ),
                        ],
                      ),
                    ],
                  ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final BrewParameterGroup group;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final columnStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                group.label(s),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // Coffee fields are only shared, so their show column is empty.
          for (final label in [
            group == BrewParameterGroup.coffee ? '' : s.parameterShow,
            s.parameterShare,
          ])
            SizedBox(
              width: 72,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: columnStyle,
              ),
            ),
        ],
      ),
    );
  }
}

class _ParameterRow extends StatelessWidget {
  const _ParameterRow({
    required this.parameter,
    required this.shown,
    required this.shared,
    required this.canUnshare,
    required this.onShown,
    required this.onShared,
  });

  final BrewParameter parameter;
  final bool shown;
  final bool shared;
  final bool canUnshare;
  final ValueChanged<bool> onShown;
  final ValueChanged<bool> onShared;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final label = parameter.label(s);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              SizedBox(
                width: 72,
                child: switch (parameter) {
                  BrewParameter(isBrewField: false) => const SizedBox.shrink(),
                  BrewParameter(canHide: false) => Tooltip(
                    message: s.parameterAlwaysShown,
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 20,
                      semanticLabel: '$label: ${s.parameterAlwaysShown}',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  _ => Checkbox(
                    key: ValueKey('parameter-show-${parameter.name}'),
                    value: shown,
                    semanticLabel: '$label: ${s.parameterShow}',
                    onChanged: (value) => onShown(value ?? true),
                  ),
                },
              ),
              SizedBox(
                width: 72,
                child: parameter.canShare
                    ? Checkbox(
                        key: ValueKey('parameter-share-${parameter.name}'),
                        value: shared,
                        semanticLabel: '$label: ${s.parameterShare}',
                        onChanged: shared && !canUnshare
                            ? null
                            : (value) => onShared(value ?? false),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          if (shared && !canUnshare)
            Padding(
              padding: const EdgeInsets.only(right: 144, bottom: 4),
              child: Text(
                s.parameterKeepOneShared,
                key: const ValueKey('parameter-last-shared-hint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
