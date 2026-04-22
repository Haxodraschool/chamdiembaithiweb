import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Orchestrates the cross-screen onboarding tutorial.
///
///   step 1 = Dashboard: highlight "Bài thi" bottom-nav tab.
///   step 2 = Exams screen: highlight "Tạo từ file đáp án" button.
///   step 3 = Import screen: highlight drop zone + "Quét phiếu thi" button.
///   step 4 = Exams screen (after pop back): note "tạo đề thi thủ công" +
///            highlight "Chấm điểm" bottom-nav tab.
///   step 5 = Scan screen: highlight exam selector → scan button → pickers.
///   step 0 = Done / skipped.
class TutorialFlow {
  TutorialFlow._();
  static final TutorialFlow instance = TutorialFlow._();

  static const _prefKey = 'tutorial_flow_step_v2';
  static const _startedKey = 'tutorial_started_once_v2';

  static const int stepClickBaiThi = 1;
  static const int stepClickImport = 2;
  static const int stepImportScreen = 3;
  static const int stepClickChamDiem = 4;
  static const int stepScanScreen = 5;
  static const int stepDone = 0;

  /// Current step. In-memory only after [markStartedOnce] — so once the tutorial
  /// has begun in any session, it will NOT auto-run again on next app launch.
  final ValueNotifier<int> step = ValueNotifier<int>(-1);

  /// Active bottom-nav tab index. Screens use this to gate coach marks so that
  /// hidden screens (built eagerly by IndexedStack) don't trigger overlays.
  final ValueNotifier<int> activeTabIndex = ValueNotifier<int>(0);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyStarted = prefs.getBool(_startedKey) ?? false;
    if (alreadyStarted) {
      // Never auto-show again. User can manually replay via Settings.
      step.value = stepDone;
    } else {
      step.value = prefs.getInt(_prefKey) ?? stepDone;
    }
  }

  Future<void> setStep(int value) async {
    step.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, value);
  }

  /// Mark the tutorial as "has been started at least once" so subsequent app
  /// launches will NOT auto-show it. Called the moment step 1 fires.
  Future<void> markStartedOnce() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_startedKey, true);
  }

  /// Advance to [next] only if currently on [expectedCurrent].
  /// Prevents regressions when user taps tabs out of order.
  Future<void> advanceIf(int expectedCurrent, int next) async {
    if (step.value == expectedCurrent) await setStep(next);
  }

  /// Restart the tutorial from step 1 (used by "Xem lại hướng dẫn" + onboarding
  /// completion on first launch). Also clears the "started once" flag so the
  /// step1 coach mark can fire again.
  Future<void> restart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_startedKey);
    await setStep(stepClickBaiThi);
  }

  Future<void> finish() => setStep(stepDone);

  bool get isActive => step.value != stepDone && step.value != -1;
}

/// Shared global keys attached to widgets in `MainShell`'s bottom nav so that
/// any screen can target them in its coach marks.
class TutorialKeys {
  static final GlobalKey baiThiTabKey = GlobalKey(debugLabel: 'tab_bai_thi');
  static final GlobalKey chamDiemTabKey =
      GlobalKey(debugLabel: 'tab_cham_diem');
}
