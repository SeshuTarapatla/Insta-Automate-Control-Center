import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/agent_client.dart';
import 'package:ia_control_center/core/agent_ws.dart';
import 'package:ia_control_center/core/ops_models.dart';
import 'package:ia_control_center/features/settings/ops_controller.dart';
import 'package:ia_control_center/features/settings/ops_tab.dart';

/// `_OpsLogPanel` calls `agentClientProvider` directly (same shape as
/// `ServiceTerminal`, which has never had a widget test either — see the
/// class doc below). Left unoverridden, its replay GET is a genuine
/// unmocked network call that leaves a pending Dio timer when the widget
/// tree is disposed, failing the test with "A Timer is still pending". This
/// adapter throws synchronously instead of attempting a real connection.
class _OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
  }

  @override
  void close({bool force = false}) {}
}

/// Overflow is a paint-time error `flutter analyze` is blind to (D19's
/// precedent, every UI checkpoint since has added one of these). The real
/// risks here: the button `Wrap` + history sidebar + log panel `Row` at the
/// app's 1024px minimum window, and a long job description/label in either.
///
/// `agentWsProvider` is stubbed rather than left real — `_OpsLogPanel`
/// listens to it directly (same as `ServiceTerminal`, which has never had a
/// widget test of its own for the same reason), and a real `AgentWsNotifier`
/// would try to read the on-disk token and schedule a reconnect timer that
/// has no business running inside a widget test.
class _FakeAgentWs extends AgentWsNotifier {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);
}

class _FakeOpsJobsController extends OpsJobsController {
  _FakeOpsJobsController(this._jobs);
  final List<OpsJob> _jobs;

  @override
  Future<List<OpsJob>> build() async => _jobs;
}

OpsJobSpec _spec(String id, {bool confirm = false, String description = 'Runs a real command.'}) => OpsJobSpec(
  id: id,
  label: id,
  description: description,
  confirm: confirm,
  consequence: confirm ? 'This cannot be undone.' : null,
);

OpsJob _job(String id, OpsJobStatus status, {DateTime? startedAt}) => OpsJob(
  id: id,
  kind: id,
  label: id,
  status: status,
  startedAt: startedAt ?? DateTime(2026, 8, 2, 12, 0),
  endedAt: status == OpsJobStatus.running ? null : DateTime(2026, 8, 2, 12, 1),
  exitCode: status == OpsJobStatus.succeeded ? 0 : (status == OpsJobStatus.failed ? 1 : null),
  currentStep: 0,
  steps: const ['step one'],
);

void main() {
  testWidgets('OpsTab lays out without overflow: every job button, a running job, and a long history', (
    tester,
  ) async {
    final specs = [
      _spec('build'),
      _spec('deploy'),
      _spec('db_backup'),
      _spec(
        'db_restore',
        confirm: true,
        description:
            'ia db restore — replaces the live database with the last Telegram backup, an unusually '
            'long description to make sure the card clips instead of overflowing.',
      ),
      _spec('purge', confirm: true),
      _spec('reset_pool'),
      _spec('helm_upgrade'),
      _spec('helm_uninstall', confirm: true),
      _spec('restart_scheduler', confirm: true),
      _spec('restart_worker', confirm: true),
    ];
    final jobs = [
      _job('running-job-with-an-unusually-long-identifier-for-a-stress-test', OpsJobStatus.running),
      _job('succeeded-1', OpsJobStatus.succeeded),
      _job('failed-1', OpsJobStatus.failed),
      _job('interrupted-1', OpsJobStatus.interrupted),
      for (var i = 0; i < 10; i++) _job('history-$i', OpsJobStatus.succeeded),
    ];

    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentWsProvider.overrideWith(() => _FakeAgentWs()),
          agentClientProvider.overrideWithValue(Dio()..httpClientAdapter = _OfflineAdapter()),
          opsSpecsProvider.overrideWith((ref) async => specs),
          opsJobsControllerProvider.overrideWith(() => _FakeOpsJobsController(jobs)),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: const Scaffold(body: OpsTab()),
        ),
      ),
    );
    // A plain fixed pump isn't enough here: unlike the other layout tests,
    // this one has a real (if offline-adapted) Dio request in flight from
    // `_OpsLogPanel`'s replay — pumpAndSettle drains that along with any
    // frames, so nothing is still pending when the tree is disposed.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('db_restore'), findsOneWidget);
  });

  testWidgets('OpsTab: no jobs run yet and nothing selected shows the empty explanations', (tester) async {
    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentWsProvider.overrideWith(() => _FakeAgentWs()),
          agentClientProvider.overrideWithValue(Dio()..httpClientAdapter = _OfflineAdapter()),
          opsSpecsProvider.overrideWith((ref) async => [_spec('build')]),
          opsJobsControllerProvider.overrideWith(() => _FakeOpsJobsController(const [])),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: const Scaffold(body: OpsTab()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No job selected'), findsOneWidget);
    expect(find.text('No jobs run yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
