import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/scheduler_models.dart';
import 'package:ia_control_center/features/flows/flow_card.dart';
import 'package:ia_control_center/features/flows/flows_controller.dart';

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
        gate: const FlowGate(ok: true, reason: 'forced', detail: 'triggered via Force run, bypassing the gate'),
        lastRun: const FlowLastRun(id: '2fc1d0d4-abcd-4e12-9f34-aaaaaaaaaaaa', state: 'COMPLETED', durationS: 214),
      ),
    );
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('Force run'), findsNothing);
  });
}
