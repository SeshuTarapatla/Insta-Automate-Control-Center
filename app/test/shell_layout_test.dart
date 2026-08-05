import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ia_control_center/core/config_models.dart';
import 'package:ia_control_center/core/connection_state.dart';
import 'package:ia_control_center/core/dependency_models.dart';
import 'package:ia_control_center/core/device_models.dart';
import 'package:ia_control_center/core/insights_models.dart';
import 'package:ia_control_center/core/library_models.dart';
import 'package:ia_control_center/core/nav_state.dart';
import 'package:ia_control_center/core/notification_models.dart';
import 'package:ia_control_center/core/onboarding.dart';
import 'package:ia_control_center/core/scheduler_models.dart';
import 'package:ia_control_center/core/service_models.dart';
import 'package:ia_control_center/features/flows/flows_controller.dart';
import 'package:ia_control_center/features/insights/insights_controller.dart';
import 'package:ia_control_center/features/library/library_controller.dart';
import 'package:ia_control_center/features/live/device_bar.dart';
import 'package:ia_control_center/features/notifications/notification_controller.dart';
import 'package:ia_control_center/features/services/dependencies_controller.dart';
import 'package:ia_control_center/features/services/services_controller.dart';
import 'package:ia_control_center/features/settings/config_controller.dart';
import 'package:ia_control_center/shell/app_shell.dart';
import 'package:ia_control_center/shell/nav_rail.dart';
import 'package:ia_control_center/ui/status.dart';

/// Overflow is a paint-time error `flutter analyze` is blind to (D19's
/// precedent). V2.5 rebuilt the flat, ungrouped `NavigationRail` into a
/// grouped, badged, collapsible rail (`shell/nav_rail.dart`) sitting above
/// whatever page is selected — the real risk is the rail's own two width
/// states (expanded/collapsed, `Ctrl+B`) each fitting inside the app's
/// 1024px floor alongside a real Overview page, which is what's mounted by
/// default.
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

class _FakeConnectionNotifier extends ConnectionNotifier {
  _FakeConnectionNotifier(this._value);
  final AgentConnection _value;
  @override
  AgentConnection build() => _value;
}

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

/// Already seen — otherwise `AppShell`'s own first-frame callback pops the
/// welcome dialog over everything this suite is trying to measure.
class _FakeOnboardingController extends OnboardingController {
  @override
  Future<bool> build() async => true;
}

/// A fixed value rather than the real persisted notifier — `NavRailCollapsedNotifier`
/// still round-trips through `shared_preferences` for the `Ctrl+B` test below (real
/// notifier, mocked prefs), but every layout-only case wants a deterministic width.
class _FakeNavRailCollapsedNotifier extends NavRailCollapsedNotifier {
  _FakeNavRailCollapsedNotifier(this._value);
  final bool _value;
  @override
  bool build() => _value;
}

FlowState _flow(String flow, {String phase = 'waiting', FlowGate gate = const FlowGate(ok: true), Map<String, dynamic>? today}) =>
    FlowState(flow: flow, switchOn: true, phase: phase, nextTriggerAt: DateTime.now().add(const Duration(minutes: 5)), gate: gate, today: today, lastRun: null);

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

Dependency _dependency(String key, {DependencyLevel level = DependencyLevel.ok}) =>
    Dependency(key: key, label: key, group: DependencyGroup.host, level: level, detail: '$key is fine', metrics: const {}, latencyMs: 8);

LibraryFolderInfo _folder(String name, {int total = 0, int entities = 0}) =>
    LibraryFolderInfo(name: name, flat: name == 'entities', total: total, entities: entities);

const _defaultLimits = {'profiles': 10, 'reels': 30, 'posts': 30, 'scrape': 300, 'follow': 60};

Burndown _burndown() {
  final days = [
    for (var i = 1; i <= 30; i++)
      BurndownDay(date: '2026-08-${i.toString().padLeft(2, '0')}', values: const {'profiles': 4, 'reels': 12, 'posts': 8, 'scraped': 180, 'followed': 42}),
  ];
  return Burndown(days: 30, limits: _defaultLimits, scan: days, scrape: days, follow: days);
}

Future<void> _pump(
  WidgetTester tester, {
  double width = 1024,
  bool? navCollapsed,
  SchedulerSnapshot? flows,
  List<ServiceStatus>? services,
  List<LibraryFolderInfo>? folders,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        connectionProvider.overrideWith(() => _FakeConnectionNotifier(AgentConnection.connected)),
        flowsControllerProvider.overrideWith(
          () => _FakeFlowsController(flows ?? SchedulerSnapshot(online: true, lastHeartbeatAt: 0, flows: {for (final f in flowOrder) f: _flow(f)})),
        ),
        flowsTickProvider.overrideWith((ref) => const Stream<int>.empty()),
        servicesControllerProvider.overrideWith(() => _FakeServicesController(services ?? [_service('adb')])),
        dependenciesControllerProvider.overrideWith(
          () => _FakeDependenciesController(
            DependencySnapshot(
              items: [
                _dependency('k3s'),
                _dependency('postgres'),
                _dependency('prefect-server'),
                _dependency('prefect-pool'),
                _dependency('adb-device'),
              ],
              ok: 5,
              warn: 0,
              fail: 0,
              checkedAt: DateTime.now(),
            ),
          ),
        ),
        burndownProvider.overrideWith((ref) async => _burndown()),
        deviceControllerProvider.overrideWith(
          () => _FakeDeviceController(const DeviceStatus(serial: '123', model: 'I2201', bridgeReachable: true, mirroring: false)),
        ),
        notificationControllerProvider.overrideWith(() => _FakeNotificationController(const [])),
        libraryFoldersControllerProvider.overrideWith(
          () => _FakeFoldersController(folders ?? [_folder('gender_valid', total: 1204), _folder('scraped', total: 191)]),
        ),
        configControllerProvider.overrideWith(() => _FakeConfigController()),
        onboardingControllerProvider.overrideWith(() => _FakeOnboardingController()),
        if (navCollapsed != null) navRailCollapsedProvider.overrideWith(() => _FakeNavRailCollapsedNotifier(navCollapsed)),
      ],
      child: const MaterialApp(debugShowCheckedModeBanner: false, home: AppShell()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('AppShell lays out without overflow at the 1024px floor: rail expanded', (tester) async {
    await _pump(tester, navCollapsed: false);
    expect(tester.takeException(), isNull);

    // Scoped to the rail itself — `OverviewPage`'s own `AppPage` title is
    // also literally "Overview", so an unscoped finder would double-count.
    final rail = find.byType(AppNavRail);
    Finder inRail(String text) => find.descendant(of: rail, matching: find.text(text));

    // Grouped, not flat (SCREENS.md §0) — the group labels only render
    // expanded.
    expect(inRail('MONITOR'), findsOneWidget);
    expect(inRail('OPERATE'), findsOneWidget);
    expect(inRail('ANALYZE'), findsOneWidget);
    expect(inRail('Overview'), findsOneWidget);
    expect(inRail('Flows'), findsOneWidget);
    expect(inRail('Review'), findsOneWidget);
    expect(inRail('Settings'), findsOneWidget);
  });

  testWidgets('AppShell lays out without overflow at the 1024px floor: rail collapsed', (tester) async {
    await _pump(tester, navCollapsed: true);
    expect(tester.takeException(), isNull);

    final rail = find.byType(AppNavRail);
    Finder inRail(String text) => find.descendant(of: rail, matching: find.text(text));

    // Icons-only: no group labels, no destination labels.
    expect(inRail('MONITOR'), findsNothing);
    expect(inRail('Overview'), findsNothing);
    expect(inRail('Review'), findsNothing);
  });

  testWidgets('AppShell lays out without overflow: flows standing by, an unhealthy service and a real review backlog', (tester) async {
    final flows = SchedulerSnapshot(
      online: true,
      lastHeartbeatAt: 0,
      flows: {
        for (final f in flowOrder)
          f: f == 'entity-scan' || f == 'entity-scrape'
              ? _flow(f, gate: const FlowGate(ok: false, reason: 'backpressure', detail: 'x >= y'))
              : _flow(f),
      },
    );
    final services = [_service('adb'), _service('vl-server', state: ServiceState.failed)];
    final folders = [_folder('gender_valid', total: 1204), _folder('scraped', total: 191)];

    await _pump(tester, navCollapsed: false, flows: flows, services: services, folders: folders);
    expect(tester.takeException(), isNull);

    final badges = tester.widgetList<CountBadge>(find.byType(CountBadge)).toList();
    expect(badges.any((b) => b.count == 1 && !b.dot), isTrue, reason: 'Services badge should show 1 unhealthy service');
    // 1204 + 191 clamps to "99+" past CountBadge's own 99 cap.
    expect(badges.any((b) => b.count == 1395 && !b.dot), isTrue, reason: 'Review badge should carry the real 1395-image backlog total');
    // Two flows are standing by (a normal, expected pipeline state, not a
    // problem) — the rail must not badge that the way it badges genuinely
    // actionable counts.
    expect(badges.any((b) => b.count == 2), isFalse, reason: 'Flows must not get a badge for flows standing by');
  });

  testWidgets('Ctrl+B toggles the real persisted collapse state', (tester) async {
    // No `navCollapsed` override here — this is the one case exercising the
    // real `NavRailCollapsedNotifier` (mocked `shared_preferences`, real
    // notifier logic), since that's what `Ctrl+B` actually drives live.
    await _pump(tester);
    expect(find.text('MONITOR'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('MONITOR'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
