import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_store.dart';
import '../auth/auth_controller.dart';
import 'journey_request.dart';

/// Options applied to every new journey search, kept on this device: wheelchair (step-free journeys), walking speed,
/// Vélib option. Set from the options of a search ("Garder pour mes prochains trajets").
class JourneyPreferences {
  const JourneyPreferences({this.wheelchair = false, this.walkingSpeed = WalkingSpeed.normal, this.bikeShare = false});

  final bool wheelchair;
  final WalkingSpeed walkingSpeed;
  final bool bikeShare;

  /// [request] with these options
  JourneyRequest apply(JourneyRequest request) =>
      request.copyWith(wheelchair: wheelchair, walkingSpeed: walkingSpeed, bikeShare: bikeShare);

  Map<String, dynamic> toJson() => {'wheelchair': wheelchair, 'walk': walkingSpeed.apiName, 'velib': bikeShare};

  factory JourneyPreferences.fromJson(Map<String, dynamic> json) => JourneyPreferences(
        wheelchair: json['wheelchair'] == true,
        walkingSpeed: WalkingSpeed.values.firstWhere((speed) => speed.apiName == json['walk'], orElse: () => WalkingSpeed.normal),
        bikeShare: json['velib'] == true,
      );
}

class JourneyPreferencesController extends Notifier<JourneyPreferences> {
  static const _key = 'journey_preferences';

  @override
  JourneyPreferences build() {
    // Reloaded when the account changes (the device copy is cleared at sign-in / sign-out)
    ref.watch(authControllerProvider);
    _load();
    return const JourneyPreferences();
  }

  Future<void> _load() async {
    final json = await ref.read(localStoreProvider).readJson(_key);
    if (json is Map<String, dynamic>) {
      state = JourneyPreferences.fromJson(json);
    }
  }

  Future<void> save(JourneyRequest request) async {
    state = JourneyPreferences(wheelchair: request.wheelchair, walkingSpeed: request.walkingSpeed, bikeShare: request.bikeShare);
    await ref.read(localStoreProvider).writeJson(_key, state.toJson());
  }
}

final journeyPreferencesProvider = NotifierProvider<JourneyPreferencesController, JourneyPreferences>(JourneyPreferencesController.new);
