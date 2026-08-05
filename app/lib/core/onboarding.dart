import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shortcuts_reference.dart';
import 'theme/tokens.dart';

/// Whether the first-run welcome dialog has been shown — persisted
/// client-side (`shared_preferences`, the same store
/// `MutedTagsController` uses) since there is no server-side concept of
/// "onboarded," this is purely local UI state.
class OnboardingController extends AsyncNotifier<bool> {
  static const _prefsKey = 'has_seen_onboarding';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> markSeen() async {
    state = const AsyncValue.data(true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }
}

final onboardingControllerProvider = AsyncNotifierProvider<OnboardingController, bool>(OnboardingController.new);

/// Shown once on first launch (`shell/app_shell.dart`), and re-openable any
/// time from the title bar's "?" affordance — a brief orientation, not a
/// guided tour: what this app is, where to look, and how to get back once
/// it's closed to the tray.
Future<void> showWelcomeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final tokens = theme.tokens;
      return AlertDialog(
        title: const Text('Welcome to the Control Center'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This is mission control for the Insta-Automate pipeline — flows, core services, '
                'the curation library, and everything they depend on, in one place.',
                style: theme.textTheme.bodyMedium,
              ),
              SizedBox(height: tokens.space.md),
              Text(
                'The rail on the left is every screen. Overview gives you the whole picture at a '
                'glance; each of the others goes deep on one part of it.',
                style: theme.textTheme.bodyMedium,
              ),
              SizedBox(height: tokens.space.md),
              Text(
                'Closing this window doesn\'t stop anything — it keeps running from the system '
                'tray. Press Ctrl+Alt+I anywhere, any app, to bring it back.',
                style: theme.textTheme.bodyMedium,
              ),
              SizedBox(height: tokens.space.md),
              Text(
                'Six themes live in Settings → Appearance, if the look here isn\'t your thing.',
                style: theme.textTheme.bodyMedium,
              ),
              SizedBox(height: tokens.space.md),
              Text(
                'Press "?" any time to see every keyboard shortcut.',
                style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              showShortcutsReference(context);
            },
            child: const Text('Show me the shortcuts'),
          ),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it')),
        ],
      );
    },
  );
}
