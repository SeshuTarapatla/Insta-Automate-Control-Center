import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/config_models.dart';
import 'package:ia_control_center/core/scheduler_models.dart';
import 'package:ia_control_center/features/flows/flow_card.dart';
import 'package:ia_control_center/features/flows/flows_controller.dart';
import 'package:ia_control_center/features/settings/config_controller.dart';

/// FlowCard is a fixed 360 px width regardless of window size (unlike the
/// Services detail pane, which is why services_layout_test.dart sweeps
/// several window sizes) — so the overflow risk here is entirely about
/// unbounded-length strings inside that fixed width, not window resizing.
/// The exact backpressure detail string from ARCHITECTURE §4.3.
const _backpressureDetail = 'scraped+follow_queued = 180 ≥ FOLLOW×3 = 180';

class _FakeFlowsController extends FlowsController {
  _FakeFlowsController(this._snapshot);
  final SchedulerSnapshot _snapshot;

  @override
  Future<SchedulerSnapshot> build() async => _snapshot;
}

/// FlowCard reads the timing keys (poll/cooldown seconds) for its always-on
/// mechanism line — this fakes the round trip real config lookups need
/// (`ConfigController.build()` otherwise hits a real `dio.get`), matching real
/// `Config._DEFAULTS` (Insta-Automate/models/meta.py) so the rendered text
/// matches what the pipeline actually uses.
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

Future<void> _render(WidgetTester tester, FlowState state, {bool pending = false}) async {
  tester.view.physicalSize = const Size(420, 520);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        flowsControllerProvider.overrideWith(
          () => _FakeFlowsController(SchedulerSnapshot(online: true, lastHeartbeatAt: 0, flows: {})),
        ),
        flowsTickProvider.overrideWith((ref) => const Stream<int>.empty()),
        configControllerProvider.overrideWith(() => _FakeConfigController()),
        if (pending) pendingCommandProvider.overrideWith(() => _AlreadyPendingNotifier()),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: FlowCard(state: state))),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('FlowCard lays out without overflow: scrape blocked by backpressure', (tester) async {
    await _render(
      tester,
      _state(
        flow: 'entity-scrape',
        gate: const FlowGate(ok: false, reason: 'backpressure', detail: _backpressureDetail),
        today: {'scraped': 42, 'limit': 300},
      ),
    );
    expect(tester.takeException(), isNull);
    // Blocked on a false condition is not a countdown to anything — no ring,
    // just the reason, so it can't be misread as "about to trigger."
    expect(find.text('Waiting on condition'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('FlowCard lays out without overflow: scrape cooling down after a real run', (tester) async {
    await _render(
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
    // The one wait that's a real, deterministic "eligible again at X" — this
    // is the only state that gets the countdown ring back.
    expect(find.text('Cooling down'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('FlowCard always shows its trigger mechanism, not just the countdown', (tester) async {
    await _render(tester, _state(flow: 'entity-follow'));
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('Runs when follow_queued has files · checked every 10s · min 20m between runs'),
      findsOneWidget,
    );
  });

  testWidgets('FlowCard names the instant path for ingest, not just its poll fallback', (tester) async {
    await _render(tester, _state(flow: 'entity-ingest'));
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('Instant on a new channel message · 10m poll as fallback'),
      findsOneWidget,
    );
  });

  testWidgets('FlowCard lays out without overflow: scan with all three counters', (tester) async {
    await _render(
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
  });

  testWidgets('FlowCard lays out without overflow: switch off', (tester) async {
    await _render(tester, _state(flow: 'entity-follow', switchOn: false));
    expect(tester.takeException(), isNull);
  });

  testWidgets('FlowCard lays out without overflow: forced trigger with a long-run last state', (
    tester,
  ) async {
    await _render(
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
    'FlowCard lays out without overflow: entity-follow with all three buttons at once',
    (tester) async {
      // Regression for a real bug caught live: the button row sat in a fixed
      // 36px SizedBox, sized for one row. Multiple buttons at once (Trigger
      // now, Reduce reserve, Stop) can wrap to a second row — `Wrap` given a
      // *tight* height constraint doesn't throw (unlike Row/Column
      // overflow), it just paints the second row outside its box, so
      // `tester.takeException()` alone would not have caught this. Asserting
      // real rendered positions is what would have. ("Run now"/"Skip wait"
      // removed — a manual trigger only ever means "run it regardless of its
      // condition," so Trigger now is now the only one.)
      await _render(
        tester,
        _state(
          flow: 'entity-follow',
          phase: 'running',
          gate: const FlowGate(ok: true, reason: 'reduce_reserve', detail: 'triggered via Reduce reserve'),
          lastRun: const FlowLastRun(id: 'run-1', state: 'RUNNING', durationS: null),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Running · reducing to reserve'), findsOneWidget);
      expect(find.text('Trigger now'), findsOneWidget);
      expect(find.text('Reduce reserve'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);

      // The button row must have grown to fit however many rows it needs
      // rather than clip any of them — the "Last run" line below has to
      // actually sit below the last button, not overlap it.
      final reduceReserveBottom = tester.getBottomLeft(find.text('Reduce reserve')).dy;
      final lastRunTop = tester.getTopLeft(find.textContaining('Last run:')).dy;
      expect(lastRunTop, greaterThanOrEqualTo(reduceReserveBottom));
    },
  );

  testWidgets('FlowCard lays out without overflow: command pending', (tester) async {
    await _render(
      tester,
      _state(
        flow: 'entity-scrape',
        phase: 'waiting',
        nextTriggerAt: DateTime.now().add(const Duration(seconds: 10)),
      ),
      pending: true,
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Command sent'), findsOneWidget);
    expect(find.text('Trigger now'), findsNothing);
  });
}
