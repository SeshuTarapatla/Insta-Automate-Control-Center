// Shared "what state is this flow really in, and how do I say so" logic for
// the pipeline nodes (`flow_node.dart`) built for SCREENS.md §2 / V2.6.
//
// This mirrors `flow_card.dart`'s private `_StatusKind`/`_kindOf`/
// `_subtitleFor`/mechanism-line derivation (D84/D93) exactly — re-derived
// here rather than imported from `flow_card.dart`, because that file stays
// untouched: it's what `overview_page.dart` renders today and is due to be
// replaced by `FlowCardCompact` in V2.7, not this checkpoint. Keep the two
// derivations in sync by hand until V2.7 lands and `flow_card.dart` goes
// away.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/scheduler_models.dart';
import '../../ui/icons.dart';
import '../../ui/status.dart';
import '../settings/config_controller.dart';

/// The left-hand gutter width shared by every node's status icon and every
/// edge's connector line, so the vertical line down the pipeline stays
/// visually continuous from node to node.
const flowNodeIconGutter = 40.0;

enum FlowStatusKind { off, running, dayPaused, cooldown, blocked, polling }

FlowStatusKind flowStatusKindOf(FlowState state) {
  if (!state.switchOn) return FlowStatusKind.off;
  if (state.phase == 'running') return FlowStatusKind.running;
  if (state.phase == 'day_paused') return FlowStatusKind.dayPaused;
  if (state.gate.ok && state.gate.reason == 'cooldown' && state.nextTriggerAt != null) {
    return FlowStatusKind.cooldown;
  }
  if (!state.gate.ok) return FlowStatusKind.blocked;
  return FlowStatusKind.polling;
}

String flowStatusLabel(FlowStatusKind kind, FlowState state) => switch (kind) {
  FlowStatusKind.off => 'skipped: switch OFF',
  FlowStatusKind.running => switch (state.gate.reason) {
    'message' => 'Running · triggered by message',
    'forced' => 'Running · forced',
    'reduce_reserve' => 'Running · reducing to reserve',
    _ => 'Running',
  },
  FlowStatusKind.dayPaused => 'Paused for the day',
  FlowStatusKind.cooldown => 'Cooling down',
  FlowStatusKind.blocked => 'Waiting on condition',
  FlowStatusKind.polling => 'Checking…',
};

/// The status's `accentEdge`/icon color, one level up from raw tokens — good
/// (running), warn (blocked), info (cooldown/polling — still "on schedule",
/// not stuck), neutral (off/paused).
StatusKind flowAccent(FlowStatusKind kind) => switch (kind) {
  FlowStatusKind.running => StatusKind.good,
  FlowStatusKind.blocked => StatusKind.warn,
  FlowStatusKind.cooldown || FlowStatusKind.polling => StatusKind.info,
  FlowStatusKind.off || FlowStatusKind.dayPaused => StatusKind.neutral,
};

PhosphorIconData Function(PhosphorIconsStyle) flowStatusIcon(FlowStatusKind kind) => switch (kind) {
  FlowStatusKind.running => AppIcons.play,
  FlowStatusKind.dayPaused => AppIcons.pause,
  FlowStatusKind.blocked => AppIcons.hourglass,
  FlowStatusKind.polling => AppIcons.sync,
  FlowStatusKind.off || FlowStatusKind.cooldown => AppIcons.schedule,
};

/// Falls back to Insta-Automate's own `Config._DEFAULTS` (meta.py) whenever
/// live config hasn't loaded yet — display-only explainer text, not the
/// authoritative value (the cooldown countdown always comes from the real
/// `next_trigger_at`), so a stale fallback here is cosmetic at worst.
const flowDefaultTimingSeconds = {
  'INGEST_POLL_WAIT': 600,
  'SCAN_POLL_WAIT': 10,
  'SCAN_WAIT': 0,
  'CLASSIFY_POLL_WAIT': 10,
  'SCRAPE_WAIT': 600,
  'SCRAPE_BUFFER': 10,
  'FOLLOW_WAIT': 1200,
  'FOLLOW_BUFFER': 10,
};

String humanizeFlowSeconds(int seconds) {
  if (seconds <= 0) return '0s';
  if (seconds % 3600 == 0) return '${seconds ~/ 3600}h';
  if (seconds % 60 == 0) return '${seconds ~/ 60}m';
  return '${seconds}s';
}

int _secondsFor(WidgetRef ref, String key) =>
    ref.watch(configControllerProvider).value?.values.limits[key] ?? flowDefaultTimingSeconds[key]!;

/// Always available, regardless of current state — the plain-language answer
/// to "what actually makes this run."
String flowMechanismLine(WidgetRef ref, String flow) => switch (flow) {
  'entity-ingest' =>
    'Instant on a new channel message · '
        '${humanizeFlowSeconds(_secondsFor(ref, 'INGEST_POLL_WAIT'))} poll as fallback',
  'entity-scan' =>
    'Runs when entities are queued · checked every '
        '${humanizeFlowSeconds(_secondsFor(ref, 'SCAN_POLL_WAIT'))} · public profiles pause '
        'above the ${ref.watch(configControllerProvider).value?.values.limits['SCAN_RESERVE_TARGET'] ?? 1000} backlog cap',
  'entity-classify' =>
    'Runs when files land in scanned/ · checked every '
        '${humanizeFlowSeconds(_secondsFor(ref, 'CLASSIFY_POLL_WAIT'))}',
  'entity-scrape' =>
    'Runs when scraped+follow_queued is below the reserve · checked every '
        '${humanizeFlowSeconds(_secondsFor(ref, 'SCRAPE_BUFFER'))} · min '
        '${humanizeFlowSeconds(_secondsFor(ref, 'SCRAPE_WAIT'))} between runs',
  'entity-follow' =>
    'Runs when follow_queued has files · checked every '
        '${humanizeFlowSeconds(_secondsFor(ref, 'FOLLOW_BUFFER'))} · min '
        '${humanizeFlowSeconds(_secondsFor(ref, 'FOLLOW_WAIT'))} between runs',
  _ => '',
};

String? flowTodayLine(FlowState state) {
  final today = state.today;
  if (today == null) return null;
  return switch (state.flow) {
    'entity-scan' =>
      'profiles ${today['profiles']}/${today['profiles_limit']} · '
          'reels ${today['reels']}/${today['reels_limit']} · '
          'posts ${today['posts']}/${today['posts_limit']}',
    'entity-scrape' => 'scraped ${today['scraped']}/${today['limit']}',
    'entity-follow' => 'followed ${today['followed']}/${today['limit']}',
    _ => null,
  };
}

/// The node's always-visible second line (SCREENS.md §2): the raw gate
/// detail when blocked — "why isn't this running" is too important to be
/// hover-only in the roomier node layout, unlike D93's card, which had to
/// push it into a tooltip — otherwise today's real counters when there are
/// any, otherwise the mechanism line.
String flowDetailLine(WidgetRef ref, FlowStatusKind kind, FlowState state) {
  if (kind == FlowStatusKind.blocked) {
    return state.gate.detail ?? state.gate.reason ?? flowMechanismLine(ref, state.flow);
  }
  return flowTodayLine(state) ?? flowMechanismLine(ref, state.flow);
}

/// mm:ss (or h:mm:ss past an hour) — same format the old cooldown ring used.
String formatFlowCountdown(Duration d) {
  final total = d.inSeconds.clamp(0, 1 << 30);
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final secondsPart = seconds.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${minutes.toString().padLeft(2, '0')}:$secondsPart';
  return '$minutes:$secondsPart';
}
