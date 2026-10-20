import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/l10n.dart';
import '../location/location_providers.dart';

/// While a list loads the first time: grey cards of its shape, pulsing (still when animations are off), instead of a
/// spinner, like Citymapper
class SkeletonCards extends StatefulWidget {
  const SkeletonCards({super.key, this.count = 3, this.height = 76});

  final int count;
  final double height;

  @override
  State<SkeletonCards> createState() => _SkeletonCardsState();
}

class _SkeletonCardsState extends State<SkeletonCards> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.colors.subtle;
    return Semantics(
      label: context.l10n.loading,
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_pulse),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.count; i++)
              Container(
                height: widget.height,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(color: context.colors.card, borderRadius: BorderRadius.circular(AppTheme.radius)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 12, width: 140, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 10),
                    Container(height: 10, width: 220, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// How fresh real-time data is: "à l'instant", "il y a 40 s", "il y a 2 min", from when [value] last brought new data
class UpdatedAgo<T> extends ConsumerStatefulWidget {
  const UpdatedAgo({super.key, required this.value});

  final AsyncValue<T> value;

  @override
  ConsumerState<UpdatedAgo<T>> createState() => _UpdatedAgoState<T>();
}

class _UpdatedAgoState<T> extends ConsumerState<UpdatedAgo<T>> {
  DateTime? _at;
  Object? _data;

  void _note() {
    final data = widget.value.value;
    if (data != null && !identical(data, _data)) {
      _data = data;
      _at = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    _note();
    final at = _at;
    if (at == null) {
      return const SizedBox.shrink();
    }
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final seconds = now.difference(at).inSeconds;
    final text = seconds < 20
        ? context.l10n.updatedJustNow
        : seconds < 60
            ? context.l10n.updatedSecondsAgo((seconds / 10).floor() * 10)
            : context.l10n.updatedMinutesAgo(seconds ~/ 60);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.rss_feed, size: 14, color: context.colors.muted),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.colors.muted)),
      ],
    );
  }
}
