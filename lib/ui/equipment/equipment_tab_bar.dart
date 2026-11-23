import 'package:flutter/material.dart';

class EquipmentTabBar extends StatefulWidget {
  const EquipmentTabBar({
    super.key,
    required this.controller,
    required this.labels,
  });

  final TabController controller;
  final List<String> labels;

  @override
  State<EquipmentTabBar> createState() => _EquipmentTabBarState();
}

class _EquipmentTabBarState extends State<EquipmentTabBar> {
  final scroll = TabBarScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = Theme.of(context).textTheme.titleSmall!;
        final scale = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        final scrollable = labels.asMap().entries.any((entry) {
          final painter = TextPainter(
            text: TextSpan(text: entry.value, style: style),
            textDirection: direction,
            textScaler: scale,
            maxLines: 1,
          )..layout();
          final tooWide = painter.width > constraints.maxWidth / labels.length;
          painter.dispose();
          return tooWide;
        });
        final bar = TabBar(
          key: const ValueKey('equipment-tabs'),
          controller: widget.controller,
          scrollController: scrollable ? scroll : null,
          isScrollable: scrollable,
          tabAlignment: scrollable ? TabAlignment.start : null,
          labelPadding: scrollable
              ? const EdgeInsets.symmetric(horizontal: 14)
              : null,
          tabs: [for (final label in labels) Tab(text: label)],
        );
        if (!scrollable) return bar;
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            setState(() {});
            return false;
          },
          child: Stack(
            alignment: AlignmentDirectional.centerEnd,
            children: [
              bar,
              ListenableBuilder(
                listenable: scroll,
                builder: (context, _) {
                  if (!scroll.hasClients ||
                      !scroll.position.hasContentDimensions ||
                      scroll.position.extentAfter <= 0.5) {
                    return const SizedBox.shrink();
                  }
                  return Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .moreButtonTooltip,
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () {
                        final position = scroll.position;
                        final advance =
                            position.viewportDimension -
                            kMinInteractiveDimension;
                        scroll.animateTo(
                          (position.pixels + advance).clamp(
                            0.0,
                            position.maxScrollExtent,
                          ),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
