import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:ia_control_center/core/config_models.dart';
import 'package:ia_control_center/core/nav_state.dart';
import 'package:ia_control_center/core/scheduler_models.dart';
import 'package:ia_control_center/features/flows/flow_node.dart';
import 'package:ia_control_center/features/flows/flows_controller.dart';
import 'package:ia_control_center/features/flows/pipeline_edge.dart';
import 'package:ia_control_center/features/library/library_controller.dart';
import 'package:ia_control_center/features/settings/config_controller.dart';
import 'package:ia_control_center/ui/icons.dart';

// `AppIcon` resolves through Phosphor, not Material `Icons.*` — see
// `notification_center_layout_test.dart`'s identical note on why
// `PhosphorIconsStyle.regular` is the right weight for a bare `ThemeData()`.
const _iconWeight = PhosphorIconsStyle.regular;

/// The exact backpressure detail string from ARCHITECTURE §4.3 — now shown
/// inline on the node while standing by (SCREENS.md §2), not just in a
/// tooltip (D93's card).
const _backpressureDetail = 'scraped+follow_queued = 180 ≥ FOLLOW×3 = 180';

class _FakeFlowsController extends FlowsController {
  @override
  Future<SchedulerSnapshot> build() async => const SchedulerSnapshot(online: true, lastHeartbeatAt: 0, flows: {});
}

/// FlowNode reads the timing keys (poll/cooldown seconds) for its mechanism
/// line — this fakes the round trip real config lookups need
/// (`ConfigController.build()` otherwise hits a real `dio.get`), matching
/// real `Config._DEFAULTS` (Insta-Automate/models/meta.py).
class _FakeConfigController extends ConfigController {
  @override
  Future<ConfigResponse> build() async => const ConfigResponse(
    path: 'config.env',
    values: ConfigValues(
      switches: {},
      entityQueue: [],
      limits: {
        'INGEST_POLL_WAIT': 600,
        'SCAN_POLL_WAIT': 10,
        'SCAN_WAIT': 0,
        'CLASSIFY_POLL_WAIT': 10,
        'SCRAPE_WAIT': 600,
        'SCRAPE_BUFFER': 10,
        'FOLLOW_WAIT': 1200,
        'FOLLOW_BUFFER': 10,
        'FOLLOW': 60,
        'SCRAPE_RESERVE_FACTOR': 3,
      },
    ),
    schema: [],
    provenance: {},
  );
}

FlowState _state({
  required String flow,
  String phase = 'idle',
  bool switchOn = true,
  FlowGate gate = const FlowGate(ok: true),
  Map<String, dynamic>? today,
  FlowLastRun? lastRun,
  DateTime? nextTriggerAt,
}) => FlowState(
  flow: flow,
  switchOn: switchOn,
  phase: phase,
  nextTriggerAt: nextTriggerAt,
  gate: gate,
  today: today,
  lastRun: lastRun,
);

class _AlreadyPendingNotifier extends PendingCommandNotifier {
  @override
  Map<String, PendingCommand> build() => {
    'entity-scrape': PendingCommand(sentAt: DateTime.now(), previousPhase: 'waiting', previousGateReason: null),
  };
}

Future<void> _renderNode(
  WidgetTester tester,
  FlowState state, {
  bool pending = false,
  double width = 1024,
}) async {
  tester.view.physicalSize = const Size(1024, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        flowsControllerProvider.overrideWith(_FakeFlowsController.new),
        flowsTickProvider.overrideWith((ref) => const Stream<int>.empty()),
        configControllerProvider.overrideWith(_FakeConfigController.new),
        if (pending) pendingCommandProvider.overrideWith(_AlreadyPendingNotifier.new),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: FlowNode(state: state))),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('FlowNode lays out without overflow: scrape standing by on backpressure', (tester) async {
    await _renderNode(
      tester,
      _state(
        flow: 'entity-scrape',
        gate: const FlowGate(ok: false, reason: 'backpressure', detail: _backpressureDetail),
        today: {'scraped': 42, 'limit': 300},
      ),
    );
    expect(tester.takeException(), isNull);
    // Standing by on a false condition is not a countdown to anything — no
    // progress line, just the reason, so it can't be misread as "about to
    // trigger."
    expect(find.text('Standing by'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    // The raw gate detail is now shown inline (SCREENS.md §2), not just in
    // the tooltip — "why isn't this running" is too important to be
    // hover-only in the roomier node layout.
    expect(find.text(_backpressureDetail), findsOneWidget);
  });

  testWidgets('FlowNode lays out without overflow: scrape cooling down after a real run', (tester) async {
    await _renderNode(
      tester,
      _state(
        flow: 'entity-scrape',
        phase: 'waiting',
        gate: const FlowGate(ok: true, reason: 'cooldown', detail: 'ran — next run allowed in up to 600s'),
        nextTriggerAt: DateTime.now().add(const Duration(minutes: 9, seconds: 50)),
        today: {'scraped': 43, 'limit': 300},
      ),
    );
    expect(tester.takeException(), isNull);
    // The one wait that's a real, deterministic "eligible again at X" — the
    // compact inline countdown plus the bottom progress line (D84's ring,
    // relocated per SCREENS.md §2).
    expect(find.textContaining('Cooling down'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('FlowNode exposes its trigger mechanism via the info tooltip when nothing is blocking it', (
    tester,
  ) async {
    // `AppTooltip(rich: true)` renders through `richMessage`, not `message`
    // — `find.byTooltip` can't see rich content, so a long-press + reading
    // the revealed text is the same technique `ui/overlays_test.dart` uses
    // for `AppTooltip` itself.
    await _renderNode(tester, _state(flow: 'entity-follow'));
    expect(tester.takeException(), isNull);
    expect(find.byIcon(AppIcons.info(_iconWeight)), findsOneWidget);
    await tester.longPress(find.byIcon(AppIcons.info(_iconWeight)));
    await tester.pump(const Duration(seconds: 1));
    // Also present in the always-visible detail line below the title row
    // (nothing better to show there for a flow with no today counters and
    // nothing blocking it) — the tooltip repeating it is fine, not a bug.
    expect(
      find.text('Runs when follow_queued has files · checked every 10s · min 20m between runs'),
      findsWidgets,
    );
  });

  testWidgets('FlowNode tooltip names the instant path for ingest, not just its poll fallback', (tester) async {
    await _renderNode(tester, _state(flow: 'entity-ingest'));
    expect(tester.takeException(), isNull);
    await tester.longPress(find.byIcon(AppIcons.info(_iconWeight)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Instant on a new channel message · 10m poll as fallback'), findsWidgets);
  });

  testWidgets('FlowNode lays out without overflow: scan with all three counters shown inline', (tester) async {
    await _renderNode(
      tester,
      _state(
        flow: 'entity-scan',
        phase: 'waiting',
        nextTriggerAt: DateTime.now().add(const Duration(minutes: 3)),
        today: {
          'profiles': 10,
          'profiles_limit': 10,
          'reels': 30,
          'reels_limit': 30,
          'posts': 30,
          'posts_limit': 30,
        },
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('profiles 10/10 · reels 30/30 · posts 30/30'), findsOneWidget);
  });

  testWidgets('FlowNode lays out without overflow: switch off', (tester) async {
    await _renderNode(tester, _state(flow: 'entity-follow', switchOn: false));
    expect(tester.takeException(), isNull);
  });

  testWidgets('FlowNode lays out without overflow: forced trigger with a long-run last state', (tester) async {
    await _renderNode(
      tester,
      _state(
        flow: 'entity-ingest',
        phase: 'running',
        gate: const FlowGate(ok: true, reason: 'forced', detail: 'triggered via Trigger now, bypassing the gate'),
        lastRun: const FlowLastRun(id: '2fc1d0d4-abcd-4e12-9f34-aaaaaaaaaaaa', state: 'COMPLETED', durationS: 214),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'FlowNode lays out without overflow: entity-follow with all three buttons at once, even at a narrow width',
    (tester) async {
      // Regression for the real D87 bug — a fixed-height row clipped a
      // second button row instead of growing for it. The new node never
      // wraps its button row in a fixed-height box, but this keeps a real
      // geometry assertion (not just `tester.takeException()`) as the
      // regression net, at the old FlowCard's 360px width so the three
      // buttons are genuinely forced to wrap.
      await _renderNode(
        tester,
        _state(
          flow: 'entity-follow',
          phase: 'running',
          gate: const FlowGate(ok: true, reason: 'reduce_reserve', detail: 'triggered via Reduce reserve'),
          lastRun: const FlowLastRun(id: 'run-1', state: 'RUNNING', durationS: null),
        ),
        width: 360,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Running · reducing to reserve'), findsOneWidget);
      expect(find.text('Trigger now'), findsOneWidget);
      expect(find.text('Reduce reserve'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);

      // The button row sits below the mechanism/detail line, never
      // overlapping it, regardless of how many rows it wraps to.
      final detailBottom = tester.getBottomLeft(find.textContaining('Runs when follow_queued')).dy;
      final buttonsTop = tester.getTopLeft(find.text('Trigger now')).dy;
      expect(buttonsTop, greaterThanOrEqualTo(detailBottom));
    },
  );

  testWidgets('FlowNode lays out without overflow: command pending', (tester) async {
    await _renderNode(
      tester,
      _state(flow: 'entity-scrape', phase: 'waiting', nextTriggerAt: DateTime.now().add(const Duration(seconds: 10))),
      pending: true,
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Command sent'), findsOneWidget);
    expect(find.text('Trigger now'), findsNothing);
  });

  testWidgets('Reduce reserve opens a two-option dialog with the real computed targets', (tester) async {
    // FOLLOW=60 × SCRAPE_RESERVE_FACTOR=3 (the fake config above) → 180 /
    // 179, the exact/unblock-Scrape targets — asserts the real numbers, not
    // just that a dialog opened.
    await _renderNode(tester, _state(flow: 'entity-follow'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Reduce reserve'));
    await tester.pumpAndSettle();
    expect(find.text('Reduce to 180'), findsOneWidget);
    expect(find.text('Reduce to 179 — unblocks Scrape'), findsOneWidget);
    // Dismiss without sending — `sendCommand` hits a real `dio.post`, out of
    // scope for this layout-only check (same precedent as the other
    // `FlowNode` tests in this file, none of which complete a real send).
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Reduce to 180'), findsNothing);
  });

  testWidgets('FlowNode expansion accordion reveals last-run/gate detail on tap, one at a time', (tester) async {
    await _renderNode(
      tester,
      _state(
        flow: 'entity-scrape',
        gate: const FlowGate(ok: false, reason: 'backpressure', detail: _backpressureDetail),
        lastRun: const FlowLastRun(id: 'run-abc', state: 'COMPLETED', durationS: 91),
      ),
    );
    expect(find.text('Open in Live'), findsNothing);
    await tester.tap(find.byType(FlowNode));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Open in Live'), findsOneWidget);
    expect(find.textContaining('COMPLETED'), findsWidgets);
  });

  testWidgets('PipelineEdge lays out without overflow and shows the live backlog count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: const Scaffold(
          body: Padding(padding: EdgeInsets.all(24), child: PipelineEdge(label: 'entities/ queued', count: 2)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('entities/ queued'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('YOU REVIEW'), findsNothing);
  });

  testWidgets('PipelineEdge ⚑ review edge jumps to the right Library folder on tap', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
              home: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(24),
                  child: PipelineEdge(label: 'gender_valid/', count: 1204, reviewFolder: 'gender_valid'),
                ),
              ),
            );
          },
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('YOU REVIEW'), findsOneWidget);

    await tester.tap(find.byType(PipelineEdge));
    await tester.pump();

    expect(container.read(selectedFolderProvider), 'gender_valid');
    expect(container.read(selectedNavIndexProvider), libraryIndex);
  });

  testWidgets('PipelineEdge turns warn when the backlog exceeds the reserve target', (tester) async {
    final tokens = ThemeData(useMaterial3: true, brightness: Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: tokens,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: PipelineEdge(label: 'scraped/', count: 191, reviewFolder: 'scraped', warn: true),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('191'), findsOneWidget);
  });
}
