import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Tracks which feature tours the user has seen.
/// Stored in Hive 'settings' box.
final featureTourProvider = StateNotifierProvider<FeatureTourNotifier, FeatureTourState>((ref) {
  return FeatureTourNotifier();
});

class FeatureTourState {
  final bool showDashboardTour;
  final int dashboardStep; // 0..N
  const FeatureTourState({this.showDashboardTour = false, this.dashboardStep = 0});

  FeatureTourState copyWith({bool? showDashboardTour, int? dashboardStep}) {
    return FeatureTourState(
      showDashboardTour: showDashboardTour ?? this.showDashboardTour,
      dashboardStep: dashboardStep ?? this.dashboardStep,
    );
  }
}

class FeatureTourNotifier extends StateNotifier<FeatureTourState> {
  FeatureTourNotifier() : super(const FeatureTourState()) {
    _init();
  }

  void _init() {
    final box = Hive.box('settings');
    final seen = box.get('dashboard_tour_done', defaultValue: false) as bool;
    if (!seen) {
      state = state.copyWith(showDashboardTour: true, dashboardStep: 0);
    }
  }

  void nextStep() {
    state = state.copyWith(dashboardStep: state.dashboardStep + 1);
  }

  void dismiss() {
    Hive.box('settings').put('dashboard_tour_done', true);
    state = state.copyWith(showDashboardTour: false);
  }
}
