import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/library_image.dart';
import 'package:ia_control_center/core/library_models.dart';
import 'package:ia_control_center/features/library/library_controller.dart';
import 'package:ia_control_center/features/library/review_page.dart';

/// `review_page.dart`'s own keyboard map (SCREENS.md §5b) and the "nothing
/// written until Apply" / "never present a partial set as the whole folder"
/// rules D90 already caught on mobile. `FileOpener.openUrl` (the `O` key) is
/// deliberately never exercised here — it shells out to the real OS via
/// win32 `ShellExecute`, same reasoning `library_layout_test.dart` already
/// follows for the tile's own "Open on Instagram" menu item.
final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

LibraryImageEntry _image(String name, {String folder = 'gender_valid', String entity = 'someone'}) =>
    LibraryImageEntry(name: name, path: '$folder/$entity/$name');

/// Records every mutating call instead of hitting a real agent — `apply()`/
/// `delete()`/`loadMore()` are all overridden directly (not just `build()`,
/// unlike `library_layout_test.dart`'s fakes), since this suite's whole point
/// is verifying those calls do or don't happen.
class _RecordingImagesController extends LibraryImagesController {
  _RecordingImagesController(this._initial);
  final LibraryImagesState _initial;

  int loadMoreCalls = 0;
  List<String>? appliedSelected;
  List<String>? deletedPaths;

  @override
  Future<LibraryImagesState> build() async => _initial;

  @override
  Future<void> loadMore() async {
    loadMoreCalls++;
    final current = state.value;
    if (current == null || !current.hasMore) return;
    final more = [for (var i = 0; i < 10; i++) _image('more$i.jpg')];
    state = AsyncValue.data(current.copyWith(images: [...current.images, ...more], hasMore: false, loadingMore: false));
  }

  @override
  Future<ApplyResult> apply(List<String> selected) async {
    appliedSelected = selected;
    return ApplyResult(target: 'gender_valid', moved: selected, trashed: const [], errors: const []);
  }

  @override
  Future<DeleteResult> delete(List<String> paths) async {
    deletedPaths = paths;
    return DeleteResult(deleted: paths, errors: const []);
  }
}

class _FakeMoveTargetsController extends MoveTargetsController {
  @override
  Future<Map<String, String>> build() async => const {};
}

/// Always pushes the review page on top of a placeholder home route (never
/// sets it as `home:` directly) — Escape and a successful Apply both call
/// `Navigator.pop()`, which needs somewhere real to land.
Future<_RecordingImagesController> _pump(
  WidgetTester tester, {
  required List<LibraryImageEntry> images,
  required int total,
  bool hasMore = false,
  String folder = 'gender_valid',
  String? entity = 'someone',
}) async {
  final controller = _RecordingImagesController(
    LibraryImagesState(images: images, total: total, hasMore: hasMore, loadingMore: false),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryImagesControllerProvider.overrideWith(() => controller),
        moveTargetsControllerProvider.overrideWith(_FakeMoveTargetsController.new),
        libraryImageBytesProvider.overrideWith((ref, path) async => _tinyPng),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => LibraryReviewPage(folder: folder, entity: entity)),
                ),
                child: const Text('open review'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open review'));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  testWidgets('Keep/Discard advance and record decisions; Up backs one and un-decides it', (tester) async {
    final controller = await _pump(tester, images: [_image('a.jpg'), _image('b.jpg'), _image('c.jpg')], total: 3);

    await _press(tester, LogicalKeyboardKey.arrowRight); // keep a -> position 1
    await _press(tester, LogicalKeyboardKey.arrowLeft); // discard b -> position 2
    await _press(tester, LogicalKeyboardKey.arrowUp); // back to position 1, un-decides b
    // b is undecided again — Space should default it to keep, not flip a
    // decision that no longer exists (it would flip to discard if it read
    // the stale `false` instead of treating a missing key as unset).
    await _press(tester, LogicalKeyboardKey.space); // b -> keep, position stays 1 (no advance)
    await _press(tester, LogicalKeyboardKey.arrowRight); // re-keep b -> position 2
    await _press(tester, LogicalKeyboardKey.arrowRight); // keep c -> position 3 (past the end)

    expect(find.textContaining('All reviewed'), findsOneWidget);

    final applyButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply batch   ⏎'));
    expect(applyButton.onPressed, isNotNull, reason: 'every loaded image is decided and nothing more to page in');

    await tester.tap(find.widgetWithText(FilledButton, 'Apply batch   ⏎'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    // The whole point of Up-then-redecide: b ends up kept, never left
    // discarded from step 2's since-reversed decision.
    expect(controller.appliedSelected, unorderedEquals(['a.jpg', 'b.jpg', 'c.jpg']));
    // A successful Apply closes the route on its own.
    expect(find.text('open review'), findsOneWidget);
  });

  testWidgets('Apply stays disabled while more pages remain, even if every loaded image is decided', (tester) async {
    final images = [for (var i = 0; i < 5; i++) _image('img$i.jpg')];
    await _pump(tester, images: images, total: 12, hasMore: true);

    for (var i = 0; i < 5; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }

    // Every *loaded* image is decided, but `hasMore` is still true — Apply
    // must stay off, or it would trash every not-yet-loaded image the way
    // D90 caught on mobile.
    final applyButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply batch   ⏎'));
    expect(applyButton.onPressed, isNull);
  });

  testWidgets('Pagination boundary: loadMore fires once the reader approaches the loaded edge, not before', (
    tester,
  ) async {
    final images = [for (var i = 0; i < 30; i++) _image('img$i.jpg')];
    final controller = await _pump(tester, images: images, total: 40, hasMore: true);

    expect(controller.loadMoreCalls, 0, reason: 'position 0 of 30 is nowhere near the loaded boundary');

    await tester.tap(find.byKey(const ValueKey('review-dot-15')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.loadMoreCalls, 1, reason: 'position 15 of 30 is within the lookahead window');
  });

  testWidgets('Esc exits without writing anything, decisions and all', (tester) async {
    final controller = await _pump(tester, images: [_image('a.jpg'), _image('b.jpg')], total: 2);

    await _press(tester, LogicalKeyboardKey.arrowRight); // decide something, then bail anyway
    await _press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('open review'), findsOneWidget, reason: 'Esc popped the review route');
    expect(controller.appliedSelected, isNull, reason: 'nothing is written until Apply — Esc must not call it');
    expect(controller.deletedPaths, isNull);
  });

  testWidgets('Del opens the same confirm dialog every other delete path uses, and Cancel writes nothing', (
    tester,
  ) async {
    final controller = await _pump(tester, images: [_image('a.jpg'), _image('b.jpg')], total: 2);

    await _press(tester, LogicalKeyboardKey.delete);
    await tester.pump();

    expect(find.text('Delete these images?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(controller.deletedPaths, isNull);
  });
}
