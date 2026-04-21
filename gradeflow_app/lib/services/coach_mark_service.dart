import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

// Re-export commonly used types for convenience
export 'package:tutorial_coach_mark/tutorial_coach_mark.dart'
    show TargetFocus, ContentAlign, ShapeLightFocus;

/// Helper to show TutorialCoachMark once per screen, tracking
/// completion via SharedPreferences.
class CoachMarkService {
  CoachMarkService._();

  static Future<bool> hasSeen(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('coach_$key') ?? false;
  }

  static Future<void> markSeen(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('coach_$key', true);
  }

  /// Reset all coach marks (used when user replays tutorial).
  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('coach_')).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  /// Build a standard target focus.
  static TargetFocus buildTarget({
    required String identify,
    required GlobalKey key,
    required String title,
    required String description,
    ContentAlign align = ContentAlign.bottom,
    ShapeLightFocus shape = ShapeLightFocus.RRect,
  }) {
    return TargetFocus(
      identify: identify,
      keyTarget: key,
      shape: shape,
      radius: 12,
      contents: [
        TargetContent(
          align: align,
          builder: (context, controller) {
            return Container(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(description,
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          height: 1.4,
                          color: Colors.white.withOpacity(0.9))),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  /// Show coach marks on a screen.
  /// Only shows once unless [force] is true.
  static Future<void> show({
    required BuildContext context,
    required String screenKey,
    required List<TargetFocus> targets,
    bool force = false,
    VoidCallback? onFinish,
  }) async {
    if (!force && await hasSeen(screenKey)) {
      onFinish?.call();
      return;
    }

    if (!context.mounted) return;

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      textSkip: 'Bỏ qua',
      textStyleSkip: GoogleFonts.dmSans(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      paddingFocus: 6,
      onFinish: () async {
        await markSeen(screenKey);
        onFinish?.call();
      },
      onSkip: () {
        markSeen(screenKey);
        onFinish?.call();
        return true;
      },
    ).show(context: context);
  }
}

