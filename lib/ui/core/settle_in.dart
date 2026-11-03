import 'package:flutter/material.dart';

/// The app's one kind of motion: something just saved settles into place
/// the way a scale reading does. Its card opens up and its figures run up
/// to their values, slowing as they arrive: a brew's water and time, a new
/// coffee's bag.
///
/// It plays once, only for a record created moments ago, only where it is
/// in view (not in a hidden tab) and never when the system asks for less
/// motion. Everywhere else [builder] gets the finished state at once.
class SettleIn extends StatefulWidget {
  const SettleIn({
    super.key,
    required this.id,
    required this.createdAtMs,
    required this.builder,
  });

  /// The record shown; another one in the same place may settle in turn.
  final String id;

  /// When the record was saved, UTC milliseconds since the epoch.
  final int createdAtMs;

  /// Builds the card given how far it has opened (`reveal`) and how far
  /// its figures have run (`fill`), both from 0 to 1.
  final Widget Function(BuildContext context, double reveal, double fill)
  builder;

  /// How recent a record must be to settle: long enough for the form to
  /// close, short enough that reopening the list later shows it still.
  static const freshFor = Duration(seconds: 6);

  /// The whole moment. Its first fifth waits for the form's sheet to slide
  /// away, so the moment is seen; a timer would do the same but outlive the
  /// widget in tests.
  static const duration = Duration(milliseconds: 1400);

  /// [child] opened to [reveal]: from the top, fading in, as a new card
  /// takes its place in a list.
  static Widget open(double reveal, Widget child) => reveal >= 1
      ? child
      : ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: reveal,
            child: Opacity(opacity: reveal, child: child),
          ),
        );

  @override
  State<SettleIn> createState() => _SettleInState();
}

class _SettleInState extends State<SettleIn>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: SettleIn.duration,
    value: 1,
  );
  late final _reveal = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.2, 0.48, curve: Curves.easeOutCubic),
  );
  late final _fill = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.36, 1, curve: Curves.easeOutCubic),
  );
  String? _considered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _considerPlaying();
  }

  @override
  void didUpdateWidget(SettleIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The same spot can show another record, like Home's latest brew.
    if (oldWidget.id != widget.id) _considerPlaying();
  }

  void _considerPlaying() {
    if (_considered == widget.id) return;
    _considered = widget.id;
    final age =
        DateTime.now().toUtc().millisecondsSinceEpoch - widget.createdAtMs;
    final play =
        age >= 0 &&
        age < SettleIn.freshFor.inMilliseconds &&
        Visibility.of(context) &&
        !MediaQuery.disableAnimationsOf(context);
    if (!play) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _reveal.dispose();
    _fill.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) =>
        widget.builder(context, _reveal.value, _fill.value),
  );
}

/// [fill] of [target] with no more decimals than [target] has, so a figure
/// running up is never wider than where it stops.
double settledShare(double target, double fill) {
  final value = target * fill;
  return target == target.roundToDouble()
      ? value.roundToDouble()
      : (value * 10).round() / 10;
}

/// [text] in the room that [settled] will take, so a figure running up
/// does not push what sits beside it or wrap it to another line.
class SteadyText extends StatelessWidget {
  const SteadyText(this.text, {super.key, required this.settled, this.style});

  final String text;

  /// The text once settled, whose width is kept from the start.
  final String settled;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => text == settled
      ? Text(text, style: style)
      : Stack(
          children: [
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Text(settled, style: style),
            ),
            Text(text, style: style),
          ],
        );
}
