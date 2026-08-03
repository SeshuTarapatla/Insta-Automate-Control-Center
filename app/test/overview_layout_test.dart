import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/dependency_models.dart';
import 'package:ia_control_center/core/device_models.dart';
import 'package:ia_control_center/core/insights_models.dart';
import 'package:ia_control_center/core/notification_models.dart';
import 'package:ia_control_center/core/scheduler_models.dart';
import 'package:ia_control_center/core/service_models.dart';
import 'package:ia_control_center/features/flows/flows_controller.dart';
import 'package:ia_control_center/features/insights/insights_controller.dart';
import 'package:ia_control_center/features/live/device_bar.dart';
import 'package:ia_control_center/features/notifications/notification_controller.dart';
import 'package:ia_control_center/features/overview/overview_page.dart';
import 'package:ia_control_center/features/services/dependencies_controller.dart';
import 'package:ia_control_center/features/services/services_controller.dart';

/// Overflow is a paint-time error `flutter analyze` is blind to (D19's
/// precedent, every UI checkpoint since has added one of these). Overview
/// pulls together six providers this app already has separate layout-test
/// coverage for individually — the real risk here is specific to composing
/// them onto one scrollable page at the app's 1024x700 floor: the two-column
/// rows, the `Wrap`ped dependency strip, and long strings inside cards that
/// are narrower here than on their own dedicated screens.
class _FakeFlowsController extends FlowsController {
  _FakeFlowsController(this._snapshot);
  final SchedulerSnapshot _snapshot;
  @override
  Future<SchedulerSnapshot> build() async => _snapshot;
}

class _FakeServicesController extends ServicesController {
  _FakeServicesController(this._services);
  final List<ServiceStatus> _services;
  @override
  Future<List<ServiceStatus>> build() async => _services;
}

class _FakeDependenciesController extends DependenciesController {
  _FakeDependenciesController(this._snapshot);
  final DependencySnapshot _snapshot;
  @override
  Future<DependencySnapshot> build() async => _snapshot;
}

class _FakeDeviceController extends DeviceController {
  _FakeDeviceController(this._status);
  final DeviceStatus _status;
  @override
  Future<DeviceStatus> build() async => _status;
}

class _FakeNotificationController extends NotificationController {
  _FakeNotificationController(this._notifications);
  final List<AppNotification> _notifications;
  @override
  Future<List<AppNotification>> build() async => _notifications;
}

FlowState _flow(String flow, {String phase = 'waiting', Map<String, dynamic>? today}) => FlowState(
  flow: flow,
  switchOn: true,
  phase: phase,
  nextTriggerAt: DateTime.now().add(const Duration(minutes: 5)),
  gate: const FlowGate(ok: true),
  today: today,
  lastRun: null,
);

ServiceStatus _service(String name, {ServiceState state = ServiceState.running}) => ServiceStatus(
  name: name,
  label: name,
  description: 'A supervised service.',
  state: state,
  origin: ServiceOrigin.supervised,
  pid: 1234,
  uptimeS: 3600,
  restartCount: 0,
  exitCode: null,
  error: null,
  probe: const ProbeResult(ok: true, latencyMs: 12, detail: 'ok', at: 0),
  hasTest: true,
  lastTest: null,
  selfHeal: true,
  autostart: true,
  terminalAvailable: true,
  canTakeover: false,
  external: null,
  portOwner: null,
  cmd: const [],
  port: 8000,
  logSeq: 0,
  receivedAt: DateTime.now(),
);

Dependency _dependency(String key, {DependencyLevel level = DependencyLevel.ok}) => Dependency(
  key: key,
  label: key,
  group: DependencyGroup.host,
  level: level,
  detail: '$key is fine',
  metrics: const {},
  latencyMs: 8,
);

AppNotification _notification(String id, int seq) => AppNotification(
  id: id,
  seq: seq,
  ts: DateTime(2026, 8, 3, 12, 0),
  msg: 'A notification with a somewhat long message to check wrapping in a narrow card, id $id.',
  imageKey: null,
  level: 'info',
  tags: const ['scrape'],
  dedupe: null,
  transient: false,
  read: false,
);

Future<void> _pump(
  WidgetTester tester, {
  required SchedulerSnapshot flows,
  required List<ServiceStatus> services,
  required DependencySnapshot dependencies,
  required Burndown burndown,
  required DeviceStatus device,
  required List<AppNotification> notifications,
}) async {
  tester.view.physicalSize = const Size(1024, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        flowsControllerProvider.overrideWith(() => _FakeFlowsController(flows)),
        flowsTickProvider.overrideWith((ref) => const Stream<int>.empty()),
        servicesControllerProvider.overrideWith(() => _FakeServicesController(services)),
        dependenciesControllerProvider.overrideWith(() => _FakeDependenciesController(dependencies)),
        burndownProvider.overrideWith((ref) async => burndown),
        deviceControllerProvider.overrideWith(() => _FakeDeviceController(device)),
        notificationControllerProvider.overrideWith(() => _FakeNotificationController(notifications)),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: const Scaffold(body: OverviewPage()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('OverviewPage lays out without overflow: every section full of real-shaped data', (tester) async {
    final flows = SchedulerSnapshot(
      online: true,
      lastHeartbeatAt: 0,
      flows: {
        for (final flow in flowOrder)
          flow: _flow(flow, today: {'scraped': 180, 'limit': 300, 'profiles': 10, 'profiles_limit': 10}),
      },
    );
    final services = [
      _service('adb'),
      _service('vl-server', state: ServiceState.unhealthy),
      _service('wsl-bridge', state: ServiceState.backoff),
    ];
    final dependencies = DependencySnapshot(
      items: [
        for (final level in DependencyLevel.values)
          for (var i = 0; i < 3; i++) _dependency('${level.name}-check-with-a-longer-name-$i', level: level),
      ],
      ok: 3,
      warn: 3,
      fail: 3,
      checkedAt: DateTime.now(),
    );
    final days = [for (var i = 0; i < 30; i++) BurndownDay(date: '2026-08-$i', values: const {'scraped': 12345})];
    final burndown = Burndown(
      days: 30,
      limits: const {'profiles': 10, 'reels': 30, 'posts': 30, 'scrape': 300, 'follow': 60},
      scan: days,
      scrape: days,
      follow: days,
    );
    const device = DeviceStatus(
      serial: '159555486700071',
      model: 'A Rather Long Phone Model Name Pro Max',
      bridgeReachable: true,
      mirroring: true,
    );
    final notifications = [for (var i = 0; i < 8; i++) _notification('n$i', i)];

    await _pump(
      tester,
      flows: flows,
      services: services,
      dependencies: dependencies,
      burndown: burndown,
      device: device,
      notifications: notifications,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('OverviewPage lays out without overflow: nothing has reported in yet', (tester) async {
    await _pump(
      tester,
      flows: const SchedulerSnapshot(online: false, lastHeartbeatAt: 0, flows: {}),
      services: const [],
      dependencies: DependencySnapshot(items: const [], ok: 0, warn: 0, fail: 0, checkedAt: DateTime.now()),
      burndown: const Burndown(days: 30, limits: {}, scan: [], scrape: [], follow: []),
      device: const DeviceStatus(serial: null, model: null, bridgeReachable: false, mirroring: false),
      notifications: const [],
    );

    expect(tester.takeException(), isNull);

    // The notifications/device row is below the fold at this window size —
    // scroll it into the cache extent before asserting it actually rendered,
    // rather than dropping the assertion (the empty state is exactly the
    // shape most likely to look "obviously nothing there" if it silently
    // failed to build).
    await tester.dragUntilVisible(
      find.text('No notifications yet.'),
      find.byType(Scrollable),
      const Offset(0, -300),
    );
    expect(find.text('No notifications yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
