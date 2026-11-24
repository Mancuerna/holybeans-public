import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:holybeans/domain/portal_protocol.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';

/// Each quantity has its own vertical scale and shares the horizontal time axis.
class PortalChart extends StatelessWidget {
  const PortalChart({super.key, required this.portal, required this.primary});
  final PortalRecording portal;
  final ShotCurve? primary;

  @override
  Widget build(BuildContext context) {
    final samples = portal.samples;
    if (samples.isEmpty) return const SizedBox.shrink();
    final machine = primary;
    final times = [for (final s in samples) s.ms + portal.offsetMs];
    final from = math.min(0, times.reduce(math.min));
    final to = math.max(
      from + 1,
      math.max(machine?.durationMs ?? 0, times.reduce(math.max)),
    );
    final breaks = {
      for (var i = 0; i < samples.length; i++)
        if (samples[i].start) i,
    };
    final colors = Theme.of(context).colorScheme;
    Widget line(
      String name,
      List<int> t,
      List<double> values,
      Set<int> gaps,
      Color color,
    ) {
      final low = values.reduce(math.min);
      final high = values.reduce(math.max);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$name   ${low.toStringAsFixed(2)} – ${high.toStringAsFixed(2)}',
          ),
          SizedBox(
            height: 48,
            child: CustomPaint(
              painter: _Trace(t, values, gaps, from, to, low, high, color),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Belka Portal', style: Theme.of(context).textTheme.titleMedium),
        line(
          'EC',
          times,
          [for (final s in samples) s.reading.ec],
          breaks,
          colors.primary,
        ),
        line(
          AppLocalizations.of(context).portalOutlet,
          times,
          [for (final s in samples) s.reading.outlet],
          breaks,
          colors.tertiary,
        ),
        if (machine != null && machine.weight.isNotEmpty)
          line(
            AppLocalizations.of(context).portalWeight,
            machine.timesMs,
            machine.weight,
            const {},
            colors.secondary,
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${from / 1000} s'),
            Text('${(to / 1000).toStringAsFixed(1)} s'),
          ],
        ),
      ],
    );
  }
}

class _Trace extends CustomPainter {
  _Trace(
    this.times,
    this.values,
    this.breaks,
    this.from,
    this.to,
    this.low,
    this.high,
    this.color,
  );
  final List<int> times;
  final List<double> values;
  final Set<int> breaks;
  final int from;
  final int to;
  final double low;
  final double high;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = 2;
    Offset? previous;
    for (var i = 0; i < times.length; i++) {
      final y = high == low ? 0.5 : (high - values[i]) / (high - low);
      final point = Offset(
        (times[i] - from) / (to - from) * size.width,
        2 + y * (size.height - 4),
      );
      if (previous != null && !breaks.contains(i)) {
        canvas.drawLine(previous, point, pen);
      } else {
        canvas.drawCircle(point, 1, pen);
      }
      previous = point;
    }
  }

  @override
  bool shouldRepaint(_Trace oldDelegate) => true;
}

class PortalAlignment extends StatefulWidget {
  const PortalAlignment({
    super.key,
    required this.portal,
    required this.primary,
    required this.onChanged,
  });
  final PortalRecording portal;
  final ShotCurve? primary;
  final ValueChanged<PortalRecording> onChanged;
  @override
  State<PortalAlignment> createState() => _PortalAlignmentState();
}

class _PortalAlignmentState extends State<PortalAlignment> {
  late int offset = widget.portal.offsetMs;
  void shift(int delta) {
    setState(() => offset += delta);
    widget.onChanged(PortalRecording(widget.portal.samples, offsetMs: offset));
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      PortalChart(
        portal: PortalRecording(widget.portal.samples, offsetMs: offset),
        primary: widget.primary,
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '−0.5 s',
            onPressed: () => shift(-500),
            icon: const Icon(Icons.remove),
          ),
          Flexible(
            child: Text(
              '${AppLocalizations.of(context).portalOffset} ${offset / 1000} s',
            ),
          ),
          IconButton(
            tooltip: '+0.5 s',
            onPressed: () => shift(500),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    ],
  );
}

Widget savedPortalAlignment(BrewFormModel model) => FutureBuilder(
  future: model.savedRecording,
  builder: (context, snapshot) {
    final existing = snapshot.data?.curve;
    final portal = existing?.portal;
    if (portal == null) return const SizedBox.shrink();
    return PortalAlignment(
      portal: model.alignedPortal ?? portal,
      primary: model.importedShot?.curve ?? existing,
      onChanged: (value) => model.alignedPortal = value,
    );
  },
);
