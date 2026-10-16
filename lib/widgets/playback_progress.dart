import 'package:flutter/material.dart';
import '../services/abstract_player_service.dart';

// Scrubbable progress bar with elapsed and total time beneath it — or, when
// [compact], either side of a thinner bar on a single line. While the thumb
// is being dragged it follows the drag rather than the live position, and
// only seeks once released.
class PlaybackProgress extends StatefulWidget {
  final AbstractPlayerService svc;
  final bool compact;
  const PlaybackProgress({super.key, required this.svc, this.compact = false});

  @override
  State<PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<PlaybackProgress> {
  double? _dragValue;

  // M:SS, or H:MM:SS when [withHours] — used for both labels whenever the
  // track is an hour or longer, so elapsed and total read the same way.
  String _format(Duration d, {required bool withHours}) {
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (!withHours) return '${d.inMinutes}:$s';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours}:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.svc;
    return StreamBuilder<Duration?>(
      stream: svc.durationStream,
      builder: (context, durSnap) {
        final duration = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: svc.positionStream,
          builder: (context, posSnap) {
            final position = posSnap.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds.toDouble();
            final value = (_dragValue ??
                    position.inMilliseconds
                        .clamp(0, duration.inMilliseconds)
                        .toDouble())
                .clamp(0, maxMs > 0 ? maxMs : 1)
                .toDouble();

            final slider = Slider(
              value: value,
              max: maxMs > 0 ? maxMs : 1,
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                setState(() => _dragValue = null);
                svc.seek(Duration(milliseconds: v.toInt()));
              },
            );
            // Equal-width digits, so the numbers don't wobble as they change.
            final withHours = duration >= const Duration(hours: 1);
            String format(Duration d) => _format(d, withHours: withHours);
            const timeStyle = TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontFeatures: [FontFeature.tabularFigures()],
            );

            if (widget.compact) {
              // Both labels sized for the widest time this track can show
              // (its duration's format, all zeros), so the bar between them
              // doesn't shift as the elapsed time ticks over.
              final labelWidth = (TextPainter(
                text: TextSpan(
                    text: format(duration).replaceAll(RegExp(r'\d'), '0'),
                    // As the Text widgets below will actually render it.
                    style: DefaultTextStyle.of(context).style.merge(timeStyle)),
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(context),
              )..layout())
                  .width
                  .ceilToDouble();
              return Row(
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Text(format(position),
                        style: timeStyle,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        softWrap: false),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: SizedBox(height: 24, child: slider),
                    ),
                  ),
                  SizedBox(
                    width: labelWidth,
                    child: Text(format(duration),
                        style: timeStyle, maxLines: 1, softWrap: false),
                  ),
                ],
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                slider,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(format(position), style: timeStyle),
                      Text(format(duration), style: timeStyle),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
