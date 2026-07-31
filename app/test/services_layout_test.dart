import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/dependency_models.dart';
import 'package:ia_control_center/core/service_models.dart';
import 'package:ia_control_center/features/services/dependencies_tab.dart';
import 'package:ia_control_center/features/services/service_detail.dart';
import 'package:ia_control_center/features/services/service_tile.dart';
import 'package:ia_control_center/features/services/services_controller.dart';

/// Overflow is a paint-time error, so it does not show up in `flutter analyze`
/// and it does not show up in an agent-side test either — it showed up in a
/// screenshot, after the fact. These render the Services widgets at both ends
/// of the window's size range and fail on the first pixel over.
///
/// The values are the awkward real ones: vl-server's `model` metric is the
/// resolved blob path, ~110 characters, which is what overflowed the metrics
/// row by 43 px the first time this screen was looked at.
const _modelPath =
    r'C:\Users\seshu\.ollama\models\blobs\sha256-16b83be682148a4d8201dbf720ea7eace5de98b69f63f05c1e7ecb5';

/// Detail-pane sizes, being the window minus the rail, the 300 px tile list and
/// the paddings. 1024×700 is the app's minimum (main.dart) and 1920 is this
/// machine's screen — that middle one matters: the 43 px overflow that started
/// this was at ~1250 and a 1400 px case did not reproduce it.
const _paneSizes = {
  'narrow (1024 window)': Size(560, 700),
  'maximized (1920 window)': Size(1250, 950),
  'wide': Size(1400, 900),
};
const _narrow = Size(560, 700);

ServiceStatus _status({
  ServiceState state = ServiceState.running,
  ServiceOrigin origin = ServiceOrigin.external,
  Map<String, dynamic>? metrics,
  String label = 'VL server',
}) {
  return ServiceStatus(
    name: 'vl-server',
    label: label,
    description: 'qwen3-vl:4b-instruct behind llama-server — gender and privacy classification.',
    state: state,
    origin: origin,
    pid: 23112,
    uptimeS: 115200,
    restartCount: 3,
    exitCode: state == ServiceState.failed ? 3 : null,
    error: null,
    probe: const ProbeResult(ok: true, latencyMs: 10.4, detail: 'GET /v1/models → 200', at: 0),
    hasTest: true,
    lastTest: TestOutcome(
      ok: true,
      summary: 'classified the fixture at 165 ms/image, 231 prompt tokens (verdict: male)',
      metrics:
          metrics ??
          {
            'ms_per_image': 165.2,
            'first_call_ms': 488.5,
            'verdict': 'male',
            'prompt_tokens': 231,
            'model': _modelPath,
          },
      durationMs: 670,
      at: 0,
    ),
    selfHeal: true,
    autostart: false,
    terminalAvailable: origin == ServiceOrigin.supervised,
    canTakeover: origin == ServiceOrigin.external,
    external: const ProcessRef(pid: 23112, name: 'python.exe', cmdline: r'D:\Coding\python.exe'),
    portOwner: const ProcessRef(pid: 23276, name: 'llama-server.exe'),
    cmd: const ['python.exe', 'start_vl_server.py', '--no-autorestart'],
    port: 11500,
    logSeq: 1,
    receivedAt: DateTime(2026, 7, 31),
  );
}

Future<void> _render(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      // A one-second ticker would still be pending when the test ends, and the
      // clock is not what is under test here.
      overrides: [uptimeTickProvider.overrideWith((ref) => const Stream<int>.empty())],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: child)),
      ),
    ),
  );
  // The terminal's replay request fails against the test HTTP override, which
  // is the state being rendered: its "nothing to show" panel. Two pumps past
  // the resize debounce so no timer outlives the test.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('ServiceDetail lays out without overflow', () {
    for (final entry in _paneSizes.entries) {
      testWidgets('${entry.key}, external with a long model path', (tester) async {
        await _render(tester, entry.value, ServiceDetail(status: _status()));
        expect(tester.takeException(), isNull);
      });

      testWidgets('${entry.key}, supervised and failed', (tester) async {
        await _render(
          tester,
          entry.value,
          ServiceDetail(
            status: _status(state: ServiceState.failed, origin: ServiceOrigin.none),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an implausibly long service name still fits', (tester) async {
      await _render(
        tester,
        _narrow,
        ServiceDetail(status: _status(label: 'A service with a name nobody would choose')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a metric value that is one long word cannot escape its chip', (tester) async {
      await _render(
        tester,
        _narrow,
        ServiceDetail(status: _status(metrics: {'blob': _modelPath.replaceAll(r'\', '')})),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('ServiceTile lays out at its fixed 300 px', (tester) async {
    await _render(
      tester,
      _narrow,
      SizedBox(
        width: 300,
        child: ServiceTile(
          status: _status(state: ServiceState.backoff, origin: ServiceOrigin.adopted),
          selected: true,
          onTap: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('DependencyRow lays out with a long detail sentence', (tester) async {
    await _render(
      tester,
      _narrow,
      DependencyRow(
        dependency: const Dependency(
          key: 'postgres',
          label: 'postgres',
          group: DependencyGroup.cluster,
          level: DependencyLevel.fail,
          detail: 'could not read the k3s postgres-secret: Unauthorized — the cluster is '
              'unreachable, so this is a credential failure rather than a database one',
          metrics: {},
          latencyMs: 10012.5,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
