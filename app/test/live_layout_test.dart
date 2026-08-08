import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ia_control_center/core/device_models.dart';
import 'package:ia_control_center/core/flow_event_models.dart';
import 'package:ia_control_center/core/flowrun_models.dart';
import 'package:ia_control_center/core/scheduler_models.dart';
import 'package:ia_control_center/features/flows/flows_controller.dart';
import 'package:ia_control_center/features/live/device_bar.dart';
import 'package:ia_control_center/features/live/live_controller.dart';
import 'package:ia_control_center/features/live/live_page.dart';
import 'package:ia_control_center/features/live/log_console.dart';
import 'package:ia_control_center/features/live/run_summary.dart';
import 'package:ia_control_center/features/live/surfaces/classify_surface.dart';
import 'package:ia_control_center/features/live/surfaces/follow_surface.dart';
import 'package:ia_control_center/features/live/surfaces/ingest_surface.dart';
import 'package:ia_control_center/features/live/surfaces/scan_surface.dart';
import 'package:ia_control_center/features/live/surfaces/scrape_surface.dart';
import 'package:ia_control_center/features/live/surfaces/surface_common.dart';

/// The Live screen's left column (run summary over the log console) is a
/// fixed 420px regardless of window size (D42's follow-up, `live_page.dart`)
/// — same overflow shape as `FlowCard` (`flows_layout_test.dart`):
/// unbounded-length real-world strings (usernames, reason text, a run id)
/// inside a fixed-width pane, not window resizing. `AgentImage` is exercised
/// with `imageKey: null` throughout, which is the real placeholder path and
/// needs no network mock.
FlowEvent _event({
  required String kind,
  String? subject,
  String? entity,
  String? verdict,
  String? reason,
  String? image,
  Map<String, dynamic> counters = const {},
  Map<String, dynamic> extra = const {},
  int seq = 1,
}) => FlowEvent(
  seq: seq,
  id: 'evt-$seq',
  ts: 1785500000.0 + seq,
  flow: 'entity-scan',
  flowRunId: 'run-1',
  kind: kind,
  entity: entity,
  subject: subject,
  image: image,
  imageKey: null,
  verdict: verdict,
  reason: reason,
  counters: counters,
  extra: extra,
);

class _FakeFlowsController extends FlowsController {
  _FakeFlowsController(this._snapshot);
  final SchedulerSnapshot _snapshot;

  @override
  Future<SchedulerSnapshot> build() async => _snapshot;
}

class _FakeLiveController extends LiveController {
  _FakeLiveController(this._state);
  final LiveState _state;

  @override
  Future<LiveState> build() async => _state;
}

class _FakeDeviceController extends DeviceController {
  _FakeDeviceController(this._status);
  final DeviceStatus _status;

  @override
  Future<DeviceStatus> build() async => _status;
}

Future<void> _render(WidgetTester tester, Widget child, Size size, {required LiveState liveState}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        flowsControllerProvider.overrideWith(
          () => _FakeFlowsController(
            SchedulerSnapshot(
              online: true,
              lastHeartbeatAt: 0,
              flows: {
                liveState.flow: FlowState(
                  flow: liveState.flow,
                  switchOn: true,
                  phase: 'running',
                  nextTriggerAt: null,
                  gate: const FlowGate(ok: true),
                  today: const {'scraped': 42, 'limit': 300},
                  lastRun: const FlowLastRun(id: 'run-1', state: 'RUNNING', durationS: null),
                ),
              },
            ),
          ),
        ),
        liveControllerProvider.overrideWith(() => _FakeLiveController(liveState)),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

// `PhosphorIconsStyle.regular` is the right weight for a bare `ThemeData()`
// in these tests — same precedent as `flows_layout_test.dart`.
const _iconWeight = PhosphorIconsStyle.regular;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final longUsername = 'a' * 60;
  final longReason = 'f=${'9' * 40} < FMIN=100 — an implausibly long detail string with no spaces at all here';

  testWidgets('LogConsole lays out without overflow: a long unbroken message and a sticky error', (tester) async {
    final state = LiveState(
      flow: 'entity-scan',
      runId: 'run-1',
      logs: [
        FlowRunLogEntry(seq: 1, ts: 0, source: 'flow', level: 'INFO', task: 'device_ready-0aa', message: 'x' * 200),
        FlowRunLogEntry(seq: 2, ts: 1, source: 'scheduler', level: 'ERROR', task: null, message: 'gate check failed: $longReason'),
      ],
      events: const [],
    );
    await _render(
      tester,
      const SizedBox(width: 420, height: 700, child: LogConsole()),
      const Size(420, 700),
      liveState: state,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('RunSummary lays out without overflow: many counters and a long run id', (tester) async {
    // entity-scan is the one flow whose live counters pass an event's own
    // counters map straight through (the pipeline already tallies added/
    // scanned per item) rather than being derived by counting matching
    // events client-side — the cheapest way to stress an implausibly large
    // counter value without synthesizing a huge event list to match it.
    final state = LiveState(
      flow: 'entity-scan',
      runId: 'a' * 64,
      logs: const [],
      events: [
        _event(
          kind: 'scan.completed',
          counters: {'added': 1234567, 'scanned': 9999999, 'skipped_public': 12, 'skipped_no_posts': 3, 'skipped_fmin': 4, 'skipped_fmax': 5},
        ),
      ],
    );
    await _render(
      tester,
      // RunSummary now sizes to its own content at the top of the left
      // column (D42's follow-up) rather than stretching to fill a fixed
      // height — a Column's non-flexible child, unbounded main-axis space,
      // exactly like `live_page.dart`'s real structure.
      SizedBox(
        width: 420,
        height: 700,
        child: Column(children: [const RunSummary(), Expanded(child: Container())]),
      ),
      const Size(420, 700),
      liveState: state,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('RunSummary lays out without overflow: live per-flow counters (follow verdict tally)', (tester) async {
    // entity-follow's counters are derived by counting follow.result
    // verdicts client-side (D40's follow-up) — a distinct code path from
    // entity-scan's pass-through above, worth its own overflow check.
    final events = [
      for (final verdict in ['FOLLOWED', 'REQUESTED', 'FOLLOWING', 'FOLLOWED_BY', 'WANTS_TO_FOLLOW', 'FAILED'])
        _event(kind: 'follow.result', subject: 'user', verdict: verdict, seq: verdict.hashCode),
    ];
    final state = LiveState(flow: 'entity-follow', runId: 'run-1', logs: const [], events: events);
    await _render(
      tester,
      // RunSummary now sizes to its own content at the top of the left
      // column (D42's follow-up) rather than stretching to fill a fixed
      // height — a Column's non-flexible child, unbounded main-axis space,
      // exactly like `live_page.dart`'s real structure.
      SizedBox(
        width: 420,
        height: 700,
        child: Column(children: [const RunSummary(), Expanded(child: Container())]),
      ),
      const Size(420, 700),
      liveState: state,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ScanSurface lays out without overflow: long username and full counters', (tester) async {
    final events = [
      _event(kind: 'scan.started', entity: longUsername, extra: {'list': 'followers', 'f1': 12345, 'f2': 67890}, seq: 1),
      for (var i = 2; i <= 10; i++)
        _event(kind: 'scan.item', subject: longUsername, counters: {'added': i, 'scanned': i}, seq: i),
    ];
    await _render(
      tester,
      SizedBox(width: 700, height: 700, child: ScanSurface(events: events)),
      const Size(700, 700),
      liveState: LiveState(flow: 'entity-scan', runId: 'run-1', logs: const [], events: events),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ClassifySurface lays out without overflow: long username verdict cards', (tester) async {
    final events = [
      for (var i = 1; i <= 5; i++)
        _event(kind: 'classify.access', subject: longUsername, verdict: i.isEven ? 'PUBLIC' : 'PRIVATE', seq: i),
    ];
    await _render(
      tester,
      SizedBox(width: 700, height: 700, child: ClassifySurface(events: events)),
      const Size(700, 700),
      liveState: LiveState(flow: 'entity-classify', runId: 'run-1', logs: const [], events: events),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ScrapeSurface lays out without overflow: skip reason with no spaces', (tester) async {
    final events = [
      _event(kind: 'scrape.started', subject: longUsername, seq: 1),
      _event(kind: 'scrape.skipped', subject: longUsername, reason: longReason, seq: 2),
      _event(kind: 'scrape.done', subject: 'other_user', counters: {'posts': 12, 'followers': 3456789, 'following': 210}, seq: 3),
    ];
    await _render(
      tester,
      SizedBox(width: 700, height: 700, child: ScrapeSurface(events: events)),
      const Size(700, 700),
      liveState: LiveState(flow: 'entity-scrape', runId: 'run-1', logs: const [], events: events),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ScrapeSurface lays out without overflow: subject still in progress stays large', (tester) async {
    // The still-in-progress subject (no done/skipped yet) is the only one
    // that should render at the large card's wider text style — everything
    // resolved renders at the same small size as history, per D40's follow-up.
    // Its image is a real (wide, 1080x198) row crop, not the composite the
    // resolved cards below it use — and a long root name to check "root: "
    // doesn't overflow the strip layout above the text.
    final events = [
      _event(
        kind: 'scrape.done',
        subject: 'other_user',
        image: 'scrape_queued/some_root/other_user.jpg',
        counters: {'posts': 12, 'followers': 3456789, 'following': 210},
        seq: 1,
      ),
      _event(kind: 'scrape.started', subject: longUsername, image: 'scrape_queued/$longUsername/$longUsername.jpg', seq: 2),
    ];
    await _render(
      tester,
      SizedBox(width: 700, height: 700, child: ScrapeSurface(events: events)),
      const Size(700, 700),
      liveState: LiveState(flow: 'entity-scrape', runId: 'run-1', logs: const [], events: events),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('scraping…'), findsOneWidget);
  });

  testWidgets('FollowSurface lays out without overflow: every verdict tone', (tester) async {
    final events = [
      for (final verdict in ['FOLLOWED', 'REQUESTED', 'FOLLOWING', 'FOLLOWED_BY', 'WANTS_TO_FOLLOW', 'FAILED'])
        _event(
          kind: 'follow.result',
          subject: longUsername,
          verdict: verdict,
          reason: longReason,
          image: 'follow_queued/$longUsername/$longUsername.jpg',
          seq: verdict.hashCode,
        ),
    ];
    await _render(
      tester,
      SizedBox(width: 700, height: 700, child: FollowSurface(events: events)),
      const Size(700, 700),
      liveState: LiveState(flow: 'entity-follow', runId: 'run-1', logs: const [], events: events),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('IngestSurface lays out without overflow: long entity name and extra badges', (tester) async {
    final events = [
      for (var i = 1; i <= 6; i++)
        _event(
          kind: 'entity.added',
          entity: longUsername,
          extra: const {'type': 'profile', 'access': 'private'},
          seq: i,
        ),
    ];
    await _render(
      tester,
      SizedBox(width: 700, height: 700, child: IngestSurface(events: events)),
      const Size(700, 700),
      liveState: LiveState(flow: 'entity-ingest', runId: 'run-1', logs: const [], events: events),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('DeviceBar lays out without overflow: a long model name, sharing the header row with flow chips', (
    tester,
  ) async {
    // Lives in the header now (D46), sharing a row with the flow-selector
    // chips rather than a bordered card of its own — narrower effective
    // width than anywhere else in this file, and the one place a long
    // device model name (not every phone reports something as short as
    // "Pixel 7") could realistically overflow.
    tester.view.physicalSize = const Size(700, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceControllerProvider.overrideWith(
            () => _FakeDeviceController(
              const DeviceStatus(
                serial: '159555486700071',
                model: 'Some Implausibly Long Manufacturer Device Model Name Pro Max Ultra',
                bridgeReachable: true,
                mirroring: true,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: const Scaffold(
            body: Row(
              children: [
                Expanded(child: Wrap(spacing: 8, children: [ChoiceChip(label: Text('Scrape'), selected: true)])),
                DeviceBar(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    // SCREENS §3 — this button and the flow's own "Stop" (`live_page.dart`)
    // used to both just say "Stop", inches apart in the same header. The
    // mirror's own now names what it stops.
    expect(find.text('Stop mirror'), findsOneWidget);
  });

  group('wrapCardWidth', () {
    test('fits a whole number of columns with no ragged trailing gutter', () {
      // 1000px available, 20px spacing, min 320: 3 columns of 320 leaves
      // real slack, so it should grow each card to fill it exactly rather
      // than leaving a visible gap after the last one.
      final width = wrapCardWidth(1000, minWidth: 320, maxWidth: 460, spacing: 20);
      const columns = 3; // floor((1000+20)/(320+20)) == 3
      expect(width * columns + 20 * (columns - 1), closeTo(1000, 0.01));
    });

    test('never grows past maxWidth even with slack to spare', () {
      final width = wrapCardWidth(2000, minWidth: 320, maxWidth: 460, spacing: 20);
      expect(width, lessThanOrEqualTo(460));
    });

    test('never shrinks below minWidth even in a too-narrow pane', () {
      final width = wrapCardWidth(200, minWidth: 320, maxWidth: 460, spacing: 20);
      expect(width, lessThanOrEqualTo(320)); // clamped to the available space itself, not stretched
    });
  });

  testWidgets('ScrapeSurface morphs without overflow: the in-progress strip resolving into the composite card', (
    tester,
  ) async {
    // The exact transition SCREENS §3 calls the "scrape before→after morph"
    // — re-pumping the same subject's events from in-progress to done
    // exercises `AnimatedReveal`'s cross-fade rather than just each static
    // shape in isolation (the two prior `ScrapeSurface` tests above).
    final inProgress = [_event(kind: 'scrape.started', subject: 'someone', image: 'scrape_queued/root/someone.jpg', seq: 1)];
    final resolved = [
      _event(
        kind: 'scrape.done',
        subject: 'someone',
        image: 'scrape_queued/root/someone.jpg',
        counters: {'posts': 4, 'followers': 55, 'following': 12},
        seq: 1,
      ),
    ];

    await _render(
      tester,
      SizedBox(width: 700, height: 700, child: ScrapeSurface(events: inProgress)),
      const Size(700, 700),
      liveState: LiveState(flow: 'entity-scrape', runId: 'run-1', logs: const [], events: inProgress),
    );
    expect(find.text('scraping…'), findsOneWidget);

    await _render(
      tester,
      SizedBox(width: 700, height: 700, child: ScrapeSurface(events: resolved)),
      const Size(700, 700),
      liveState: LiveState(flow: 'entity-scrape', runId: 'run-1', logs: const [], events: resolved),
    );
    // AnimatedReveal keeps both children mounted mid cross-fade — settle it.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('scraping…'), findsNothing);
  });

  testWidgets('LogConsole search: highlights matches, steps with Enter/Shift+Enter, and Esc clears', (tester) async {
    final state = LiveState(
      flow: 'entity-scan',
      runId: 'run-1',
      logs: [
        FlowRunLogEntry(seq: 1, ts: 0, source: 'flow', level: 'INFO', task: null, message: 'Opening profile @needle_one'),
        FlowRunLogEntry(seq: 2, ts: 1, source: 'flow', level: 'INFO', task: null, message: 'Nothing interesting here'),
        FlowRunLogEntry(seq: 3, ts: 2, source: 'flow', level: 'INFO', task: null, message: 'Found @needle_two, scanning'),
      ],
      events: const [],
    );
    await _render(
      tester,
      const SizedBox(width: 700, height: 700, child: LogConsole()),
      const Size(700, 700),
      liveState: state,
    );
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField).first, 'needle');
    // The search box debounces like `SearchField` (250ms) before it
    // actually filters/highlights.
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(find.text('2 of 2'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(find.text('1 of 2'), findsNothing);
  });

  testWidgets('LogConsole renders a JSON-shaped message without overflow', (tester) async {
    final payload = '{"key": "${'x' * 120}", "nested": {"a": 1, "b": [1, 2, 3]}}';
    final state = LiveState(
      flow: 'entity-ingest',
      runId: 'run-1',
      logs: [FlowRunLogEntry(seq: 1, ts: 0, source: 'flow', level: 'INFO', task: null, message: payload)],
      events: const [],
    );
    await _render(
      tester,
      const SizedBox(width: 420, height: 400, child: LogConsole()),
      const Size(420, 400),
      liveState: state,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('LivePage lays out without overflow at the real observed window size and expands/restores each pane', (
    tester,
  ) async {
    // 1168 × 973 is SCREENS §3's own measured body size for this screen
    // (OBSERVED.md, D97) — the size the old hardcoded-420px column was
    // tuned against and everything else was guessed for.
    tester.view.physicalSize = const Size(1168, 973);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final liveState = LiveState(
      flow: 'entity-scrape',
      runId: 'run-1',
      logs: [FlowRunLogEntry(seq: 1, ts: 0, source: 'flow', level: 'INFO', task: null, message: 'Opening profile @someone')],
      events: [_event(kind: 'scrape.started', subject: 'someone', image: 'scrape_queued/root/someone.jpg', seq: 1)],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          flowsControllerProvider.overrideWith(
            () => _FakeFlowsController(
              SchedulerSnapshot(
                online: true,
                lastHeartbeatAt: 0,
                flows: {
                  'entity-scrape': FlowState(
                    flow: 'entity-scrape',
                    switchOn: true,
                    phase: 'running',
                    nextTriggerAt: null,
                    gate: const FlowGate(ok: true),
                    today: const {'scraped': 42, 'limit': 300},
                    lastRun: const FlowLastRun(id: 'run-1', state: 'RUNNING', durationS: null),
                  ),
                },
              ),
            ),
          ),
          liveControllerProvider.overrideWith(() => _FakeLiveController(liveState)),
          deviceControllerProvider.overrideWith(
            () => _FakeDeviceController(const DeviceStatus(serial: '1', model: 'Pixel 7', bridgeReachable: true, mirroring: false)),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: const Scaffold(body: LivePage()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    // Both panes visible side by side, the resizable handle between them.
    expect(find.text('LOGS'), findsOneWidget);
    expect(find.text('VISUALIZATION'), findsOneWidget);
    expect(find.byKey(const ValueKey('resizable_split_handle:live.split')), findsOneWidget);

    // Expand the visualization pane — the log pane's own frame disappears
    // entirely rather than just losing its content (SCREENS §3's "just show
    // me the images" mode). Two ⤢ buttons exist (one per pane); the second
    // is visualization's, matching `first`/`second` order in `live_page.dart`.
    final expandButtons = find.widgetWithIcon(IconButton, PhosphorIcons.arrowsOut(_iconWeight));
    expect(expandButtons, findsNWidgets(2));
    await tester.tap(expandButtons.last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('LOGS'), findsNothing);
    expect(find.text('VISUALIZATION'), findsOneWidget);
    expect(find.byKey(const ValueKey('resizable_split_handle:live.split')), findsNothing);

    // Restore — both panes and the handle come back.
    await tester.tap(find.widgetWithIcon(IconButton, PhosphorIcons.arrowsIn(_iconWeight)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('LOGS'), findsOneWidget);
    expect(find.text('VISUALIZATION'), findsOneWidget);
    expect(find.byKey(const ValueKey('resizable_split_handle:live.split')), findsOneWidget);
  });

  testWidgets('LivePage lays out without overflow at the app\'s 1024×700 floor', (tester) async {
    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final liveState = LiveState(flow: 'entity-follow', runId: 'run-1', logs: const [], events: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          flowsControllerProvider.overrideWith(
            () => _FakeFlowsController(
              SchedulerSnapshot(
                online: true,
                lastHeartbeatAt: 0,
                flows: {
                  'entity-follow': FlowState(
                    flow: 'entity-follow',
                    switchOn: true,
                    phase: 'waiting',
                    nextTriggerAt: null,
                    gate: const FlowGate(ok: true),
                    today: const {'followed': 5, 'limit': 300},
                    lastRun: null,
                  ),
                },
              ),
            ),
          ),
          liveControllerProvider.overrideWith(() => _FakeLiveController(liveState)),
          deviceControllerProvider.overrideWith(
            () => _FakeDeviceController(const DeviceStatus(serial: null, model: null, bridgeReachable: false, mirroring: false)),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: const Scaffold(body: LivePage()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
