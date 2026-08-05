import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/config_models.dart';
import 'package:ia_control_center/core/connection_state.dart';
import 'package:ia_control_center/core/dependency_models.dart';
import 'package:ia_control_center/core/device_models.dart';
import 'package:ia_control_center/core/insights_models.dart';
import 'package:ia_control_center/core/library_models.dart';
import 'package:ia_control_center/core/notification_models.dart';
import 'package:ia_control_center/core/scheduler_models.dart';
import 'package:ia_control_center/core/service_models.dart';
import 'package:ia_control_center/features/flows/flows_controller.dart';
import 'package:ia_control_center/features/insights/insights_controller.dart';
import 'package:ia_control_center/features/library/library_controller.dart';
import 'package:ia_control_center/features/live/device_bar.dart';
import 'package:ia_control_center/features/notifications/notification_controller.dart';
import 'package:ia_control_center/features/overview/overview_page.dart';
import 'package:ia_control_center/features/services/dependencies_controller.dart';
import 'package:ia_control_center/features/services/services_controller.dart';
import 'package:ia_control_center/features/settings/config_controller.dart';

/// Overflow is a paint-time error `flutter analyze` is blind to (D19's
/// precedent, every UI checkpoint since has added one of these). V2.7
/// rebuilt Overview as a bento grid (SCREENS.md §1) — the real risk here is
/// specific to the three named breakpoints (DESIGN_SYSTEM §7: compact <1100,
/// medium 1100–1500, wide ≥1500) each arranging the same eight tiles
/// differently, plus the hero tile's four `StatusKind`s driving different
/// content/action combinations.
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

class _FakeFoldersController extends LibraryFoldersController {
  _FakeFoldersController(this._folders);
  final List<LibraryFolderInfo> _folders;
  @override
  Future<List<LibraryFolderInfo>> build() async => _folders;
}

/// Replaces the real `Timer.periodic` + `dio.get('/api/health')` round trip
/// (`ConnectionNotifier.build()`) with a fixed value — the same reasoning
/// every other fake controller here has, plus avoiding a real periodic timer
/// ticking during the test.
class _FakeConnectionNotifier extends ConnectionNotifier {
  _FakeConnectionNotifier(this._value);
  final AgentConnection _value;
  @override
  AgentConnection build() => _value;
}

/// The embedded flow/pipeline widgets read timing config for their
/// mechanism line — fakes the round trip real config lookups need
/// (`ConfigController.build()` otherwise hits a real `dio.get`).
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

FlowState _flow(String flow, {String phase = 'waiting', FlowGate gate = const FlowGate(ok: true), Map<String, dynamic>? today}) =>
    FlowState(
      flow: flow,
      switchOn: true,
      phase: phase,
      nextTriggerAt: DateTime.now().add(const Duration(minutes: 5)),
      gate: gate,
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

LibraryFolderInfo _folder(String name, {int total = 0, int entities = 0}) =>
    LibraryFolderInfo(name: name, flat: name == 'entities', total: total, entities: entities);

const _defaultLimits = {'profiles': 10, 'reels': 30, 'posts': 30, 'scrape': 300, 'follow': 60};

Burndown _burndown({Map<String, int?> limits = _defaultLimits}) {
  final days = [for (var i = 1; i <= 30; i++) BurndownDay(date: '2026-08-${i.toString().padLeft(2, '0')}', values: const {'profiles': 4, 'reels': 12, 'posts': 8, 'scraped': 180, 'followed': 42})];
  return Burndown(days: 30, limits: limits, scan: days, scrape: days, follow: days);
}

Future<void> _pump(
  WidgetTester tester, {
  double width = 1300,
  AgentConnection connection = AgentConnection.connected,
  SchedulerSnapshot? flows,
  List<ServiceStatus>? services,
  DependencySnapshot? dependencies,
  Burndown? burndown,
  DeviceStatus? device,
  List<AppNotification>? notifications,
  List<LibraryFolderInfo>? folders,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        connectionProvider.overrideWith(() => _FakeConnectionNotifier(connection)),
        flowsControllerProvider.overrideWith(
          () => _FakeFlowsController(flows ?? SchedulerSnapshot(online: true, lastHeartbeatAt: 0, flows: {for (final f in flowOrder) f: _flow(f)})),
        ),
        flowsTickProvider.overrideWith((ref) => const Stream<int>.empty()),
        servicesControllerProvider.overrideWith(() => _FakeServicesController(services ?? [_service('adb')])),
        dependenciesControllerProvider.overrideWith(
          () => _FakeDependenciesController(
            dependencies ?? DependencySnapshot(items: [_dependency('k3s')], ok: 1, warn: 0, fail: 0, checkedAt: DateTime.now()),
          ),
        ),
        burndownProvider.overrideWith((ref) async => burndown ?? _burndown()),
        deviceControllerProvider.overrideWith(
          () => _FakeDeviceController(device ?? const DeviceStatus(serial: '123', model: 'I2201', bridgeReachable: true, mirroring: false)),
        ),
        notificationControllerProvider.overrideWith(() => _FakeNotificationController(notifications ?? [_notification('n0', 0)])),
        libraryFoldersControllerProvider.overrideWith(
          () => _FakeFoldersController(folders ?? [_folder('gender_valid', total: 1204), _folder('scraped', total: 191)]),
        ),
        configControllerProvider.overrideWith(() => _FakeConfigController()),
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
  for (final width in [1024.0, 1300.0, 1700.0]) {
    testWidgets('OverviewPage lays out without overflow at ${width.round()}px: every section full of real-shaped data', (
      tester,
    ) async {
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
      const device = DeviceStatus(serial: '159555486700071', model: 'A Rather Long Phone Model Name Pro Max', bridgeReachable: true, mirroring: true);
      final notifications = [for (var i = 0; i < 8; i++) _notification('n$i', i)];
      final folders = [_folder('entities', total: 445), _folder('scanned', total: 1882), _folder('gender_valid', total: 1204), _folder('scraped', total: 191)];

      await _pump(
        tester,
        width: width,
        flows: flows,
        services: services,
        dependencies: dependencies,
        device: device,
        notifications: notifications,
        folders: folders,
      );

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('OverviewPage lays out without overflow: nothing has reported in yet', (tester) async {
    await _pump(
      tester,
      connection: AgentConnection.disconnected,
      flows: const SchedulerSnapshot(online: false, lastHeartbeatAt: 0, flows: {}),
      services: const [],
      dependencies: DependencySnapshot(items: const [], ok: 0, warn: 0, fail: 0, checkedAt: DateTime.now()),
      burndown: const Burndown(days: 30, limits: {}, scan: [], scrape: [], follow: []),
      device: const DeviceStatus(serial: null, model: null, bridgeReachable: false, mirroring: false),
      notifications: const [],
      folders: const [],
    );

    expect(tester.takeException(), isNull);

    await tester.dragUntilVisible(find.text('No notifications yet.'), find.byType(Scrollable), const Offset(0, -300));
    expect(find.text('No notifications yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('Hero tile', () {
    testWidgets('good: nothing wrong', (tester) async {
      await _pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('All five flows running normally'), findsOneWidget);
    });

    testWidgets('bad: agent disconnected takes priority over everything else', (tester) async {
      await _pump(tester, connection: AgentConnection.disconnected);
      expect(tester.takeException(), isNull);
      expect(find.text('Agent disconnected'), findsOneWidget);
    });

    testWidgets('bad: a failed service', (tester) async {
      await _pump(tester, services: [_service('vl-server', state: ServiceState.failed)]);
      expect(tester.takeException(), isNull);
      expect(find.text('vl-server has failed'), findsOneWidget);
    });

    testWidgets('good: a flow standing by on its condition is normal, not a warning', (tester) async {
      // A flow with `gate.ok: false` (backpressure/day_limit/no_work) isn't
      // stuck — it just hasn't reached its condition yet, and will pick
      // back up the moment it does. This must not read as "needs
      // attention": the hero should stay in its good state exactly as if
      // every flow were idle-and-waiting normally.
      await _pump(
        tester,
        flows: SchedulerSnapshot(
          online: true,
          lastHeartbeatAt: 0,
          flows: {
            for (final f in flowOrder)
              f: f == 'entity-scan'
                  ? _flow(f, gate: const FlowGate(ok: false, reason: 'backpressure', detail: 'x >= y'))
                  : _flow(f),
          },
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('All five flows running normally'), findsOneWidget);
      // "Go to Flows" is unconditional, not tied to any warning state.
      expect(find.text('Go to Flows'), findsWidgets);
    });

    testWidgets('good, but a curation backlog waiting still surfaces a Review action', (tester) async {
      await _pump(tester, folders: [_folder('gender_valid', total: 1204)]);
      expect(tester.takeException(), isNull);
      expect(find.text('All five flows running normally'), findsOneWidget);
      expect(find.textContaining('Review 1204 waiting'), findsWidgets);
    });
  });
}
