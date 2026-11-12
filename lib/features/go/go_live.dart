import 'package:flutter/services.dart';

import '../../core/api/models.dart';
import '../../core/platform/live_journey.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/l10n.dart';
import 'go_guidance.dart';
import 'go_glance.dart';
import 'go_instruction.dart';
import 'go_state.dart';
import 'go_tracker.dart';

/// What the system notification (Android) shows of [state], like a live activity (design 3A): the same moment as GO's
/// banner ([goGlance]: what to do as its title, its figure then where under it, the figure also as the chip), the
/// platform, the line of the ride as a badge, the progress along the steps and the arrival. Not for an arrived
/// journey: the notification is gone then.
LiveJourneyUpdate goLiveUpdate(GoState state, DateTime now) {
  final glance = goGlance(state, now);
  final tracker = state.tracker;
  final progress = state.progress;
  final step = tracker.stepOf(progress);

  final chip = glance.heroText ?? switch (progress.phase) {
    GoPhase.onBoard =>
      tracker.stopsLeft(progress) <= 1 ? currentL10n.goChipGetOff : currentL10n.stopsCount(tracker.stopsLeft(progress)),
    GoPhase.waiting when step != null =>
      currentL10n.minutesShort(
          (tracker.expectedDeparture(step, progress, state.currentVehicle).difference(now).inSeconds / 60).ceil().clamp(0, 999)),
    _ => currentL10n.minutesShort((tracker.metersLeft(progress) / defaultWalkSpeed / 60).ceil()),
  };
  // The platform as soon as it is known: the subtitle while waiting, the next ride's otherwise
  final platform = goPlatformText(state);
  final status = [
    chip,
    if (glance.place case final place? when place.isNotEmpty) place,
    if (platform != null && !(glance.place ?? '').contains(platform) && !glance.kicker.toLowerCase().contains(platform)) platform,
  ].join(' · ');

  return LiveJourneyUpdate(
    title: glance.action,
    status: status,
    progress: journeySecondsDone(tracker, progress).round(),
    mode: _liveMode(step?.section),
    chip: chip,
    info: currentL10n.goArrival(formatClock(tracker.eta(progress, state.currentVehicle))),
    line: switch (step?.section.line) {
      final line? when step!.isRide && (line.name ?? '').isNotEmpty => LiveJourneyLine(
          name: line.name!,
          color: '#${line.color ?? '666666'}',
          textColor: '#${line.textColor ?? 'FFFFFF'}',
          mode: line.mode.name,
        ),
      _ => null,
    },
    segments: [
      for (final goStep in tracker.steps)
        LiveJourneySegment(
          seconds: goStep.section.duration,
          color: goStep.isRide && goStep.section.line?.color != null ? '#${goStep.section.line!.color}' : '#9E9E9E',
        ),
    ],
  );
}

/// The notification's icon of the step in progress
String _liveMode(JourneySection? section) => switch (section?.kind) {
      SectionKind.transit => switch (section?.line?.mode) {
          TransportMode.metro => 'metro',
          TransportMode.rer || TransportMode.transilien || TransportMode.ter => 'train',
          TransportMode.tram => 'tram',
          _ => 'bus',
        },
      SectionKind.transfer => 'transfer',
      _ => 'walk',
    };

/// Whether [alert] also rings in a notification while the app isn't on screen (design 3B): only what must be done
/// now, so that it stays rare: get off, a platform changed, a vehicle missed or cancelled
bool goAlertRings(GoAlert alert) =>
    alert.kind == 'alight' ||
    (alert.kind == 'platform' && alert.urgent) ||
    alert.id.startsWith('missed-') ||
    alert.id.startsWith('cancel-');

/// An alert felt in the app: each kind its own pattern
void feelGoAlert(GoAlert alert) {
  SystemSound.play(SystemSoundType.alert);
  void pulses(int count, Duration gap, void Function() pulse) {
    for (var i = 0; i < count; i++) {
      Future.delayed(gap * i, pulse);
    }
  }

  switch (alert.kind) {
    case 'prepare':
      pulses(2, const Duration(milliseconds: 220), HapticFeedback.mediumImpact);
    case 'alight':
      pulses(3, const Duration(milliseconds: 450), HapticFeedback.heavyImpact);
    case 'platform':
      HapticFeedback.selectionClick();
    case 'urgent':
      pulses(2, const Duration(milliseconds: 300), HapticFeedback.heavyImpact);
    default:
      HapticFeedback.mediumImpact();
  }
}
