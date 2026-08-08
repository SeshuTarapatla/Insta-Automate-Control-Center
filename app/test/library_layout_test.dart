import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:ia_control_center/core/library_image.dart';
import 'package:ia_control_center/core/library_models.dart';
import 'package:ia_control_center/features/library/library_controller.dart';
import 'package:ia_control_center/features/library/library_grid.dart';
import 'package:ia_control_center/features/library/library_page.dart';
import 'package:ia_control_center/features/library/library_rail.dart';
import 'package:ia_control_center/features/library/library_tile.dart';
import 'package:ia_control_center/features/library/library_toolbar.dart';
import 'package:ia_control_center/ui/icons.dart';

const _iconWeight = PhosphorIconsStyle.regular;

/// Overflow is a paint-time error `flutter analyze` and every agent-side test
/// are blind to (D19's precedent, most recently exercised by
/// `live_layout_test.dart`) — real risk here is real-world-length usernames
/// and entity roots inside fixed-width rail/toolbar rows, and the three-column
/// `LibraryPage` layout squeezed to the app's 1024px minimum window.
///
/// `libraryThumbBytesProvider` is overridden to a tiny real PNG rather than
/// `imageKey: null`-style skipping (unlike `AgentImage`, `LibraryThumbnail`
/// has no null-path placeholder mode — it always fetches by path), so
/// `Image.memory` has something real to decode instead of hitting the network.
final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class _FakeFoldersController extends LibraryFoldersController {
  _FakeFoldersController(this._folders);
  final List<LibraryFolderInfo> _folders;
  @override
  Future<List<LibraryFolderInfo>> build() async => _folders;
}

class _FakeEntitiesController extends LibraryEntitiesController {
  _FakeEntitiesController(this._entities);
  final List<LibraryEntityInfo> _entities;
  @override
  Future<List<LibraryEntityInfo>> build() async => _entities;
}

class _FakeImagesController extends LibraryImagesController {
  _FakeImagesController(this._state);
  final LibraryImagesState _state;
  @override
  Future<LibraryImagesState> build() async => _state;
}

class _FakeMoveTargetsController extends MoveTargetsController {
  _FakeMoveTargetsController(this._targets);
  final Map<String, String> _targets;
  @override
  Future<Map<String, String>> build() async => _targets;
}

class _FixedFolder extends SelectedFolderNotifier {
  _FixedFolder(this._value);
  final String? _value;
  @override
  String? build() => _value;
}

class _FixedEntity extends SelectedEntityNotifier {
  _FixedEntity(this._value);
  final String? _value;
  @override
  String? build() => _value;
}

class _FixedSelection extends LibrarySelectionNotifier {
  _FixedSelection(this._value);
  final LibrarySelectionState _value;
  @override
  LibrarySelectionState build() => _value;
}

class _FixedZoom extends LibraryZoomNotifier {
  _FixedZoom(this._value);
  final LibraryZoom _value;
  @override
  LibraryZoom build() => _value;
}

LibraryImageEntry _image(String name, {String folder = 'scrape_queued', String entity = 'someone'}) =>
    LibraryImageEntry(name: name, path: '$folder/$entity/$name');

Future<void> _render(
  WidgetTester tester,
  Widget child,
  Size size, {
  required List<LibraryFolderInfo> folders,
  List<LibraryEntityInfo> entities = const [],
  required LibraryImagesState images,
  Map<String, String> targets = const {},
  String? selectedFolder,
  String? selectedEntity,
  LibrarySelectionState selection = const LibrarySelectionState(),
  LibraryZoom? zoom,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryFoldersControllerProvider.overrideWith(() => _FakeFoldersController(folders)),
        libraryEntitiesControllerProvider.overrideWith(() => _FakeEntitiesController(entities)),
        libraryImagesControllerProvider.overrideWith(() => _FakeImagesController(images)),
        moveTargetsControllerProvider.overrideWith(() => _FakeMoveTargetsController(targets)),
        libraryThumbBytesProvider.overrideWith((ref, params) async => _tinyPng),
        selectedFolderProvider.overrideWith(() => _FixedFolder(selectedFolder)),
        selectedEntityProvider.overrideWith(() => _FixedEntity(selectedEntity)),
        librarySelectionProvider.overrideWith(() => _FixedSelection(selection)),
        if (zoom != null) libraryZoomProvider.overrideWith(() => _FixedZoom(zoom)),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  final longUsername = 'a' * 60;
  final longEntity = 'b' * 50;

  final folders = [
    const LibraryFolderInfo(name: 'entities', flat: true, total: 433, entities: 0),
    const LibraryFolderInfo(name: 'scanned', flat: false, total: 0, entities: 0),
    const LibraryFolderInfo(name: 'gender_valid', flat: false, total: 0, entities: 0),
    const LibraryFolderInfo(name: 'gender_invalid', flat: false, total: 0, entities: 0),
    LibraryFolderInfo(name: 'scrape_queued', flat: false, total: 99999, entities: 110),
    const LibraryFolderInfo(name: 'scraped', flat: false, total: 22, entities: 2),
    const LibraryFolderInfo(name: 'follow_queued', flat: false, total: 180, entities: 9),
  ];

  final manyImages = [
    for (var i = 0; i < 30; i++) _image(i == 0 ? '$longUsername.jpg' : 'user$i.jpg', entity: longEntity),
  ];

  testWidgets('LibraryGrid lays out without overflow: many tiles, a 60-char filename, every zoom level', (
    tester,
  ) async {
    for (final zoom in LibraryZoom.values) {
      await _render(
        tester,
        SizedBox(
          width: 1024,
          height: 700,
          child: LibraryGrid(entityLabel: longEntity, onDeleteRequested: () {}),
        ),
        const Size(1024, 700),
        folders: folders,
        images: LibraryImagesState(images: manyImages, total: 99999, hasMore: true, loadingMore: false),
        selectedFolder: 'scrape_queued',
        selectedEntity: longEntity,
        zoom: zoom,
      );
      expect(tester.takeException(), isNull, reason: 'zoom level $zoom');
    }
  });

  testWidgets('LibraryToolbar lays out without overflow: long folder/entity/target names, a big selection', (
    tester,
  ) async {
    final selected = {for (final img in manyImages) img.name};
    await _render(
      tester,
      SizedBox(
        width: 700,
        child: LibraryToolbar(folder: 'scrape_queued', entity: longEntity),
      ),
      const Size(700, 200),
      folders: folders,
      images: LibraryImagesState(images: manyImages, total: 99999, hasMore: true, loadingMore: false),
      targets: const {'scrape_queued': 'follow_queued'},
      selectedFolder: 'scrape_queued',
      selectedEntity: longEntity,
      selection: LibrarySelectionState(selected: selected, anchorIndex: 0, focusedIndex: 0),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('FolderRail lays out without overflow: a huge total on a narrow production-width column', (
    tester,
  ) async {
    await _render(
      tester,
      const SizedBox(width: 220, height: 700, child: FolderRail()),
      const Size(220, 700),
      folders: folders,
      images: LibraryImagesState.empty,
      selectedFolder: 'scrape_queued',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('EntityList lays out without overflow: a 50-char entity name and a huge count', (tester) async {
    final entities = [
      LibraryEntityInfo(root: longEntity, count: 99999),
      for (var i = 0; i < 20; i++) LibraryEntityInfo(root: 'entity$i', count: i),
    ];
    await _render(
      tester,
      const SizedBox(width: 220, height: 700, child: EntityList()),
      const Size(220, 700),
      folders: folders,
      entities: entities,
      images: LibraryImagesState.empty,
      selectedFolder: 'scrape_queued',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('LibraryPage lays out without overflow at the app minimum window width', (tester) async {
    final entities = [LibraryEntityInfo(root: longEntity, count: 30), const LibraryEntityInfo(root: 'other', count: 4)];
    await _render(
      tester,
      const SizedBox(width: 1024, height: 700, child: LibraryPage()),
      const Size(1024, 700),
      folders: folders,
      entities: entities,
      images: LibraryImagesState(images: manyImages, total: 99999, hasMore: true, loadingMore: false),
      targets: const {'scrape_queued': 'follow_queued'},
      selectedFolder: 'scrape_queued',
      selectedEntity: longEntity,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('LibraryPage lays out without overflow at a real production width, flat folder selected', (
    tester,
  ) async {
    final entityImages = [
      for (var i = 0; i < 40; i++) _image('post-${'c' * 30}_$i.jpg', folder: 'entities', entity: ''),
    ];
    await _render(
      tester,
      const SizedBox(width: 1250, height: 900, child: LibraryPage()),
      const Size(1250, 900),
      folders: folders,
      images: LibraryImagesState(images: entityImages, total: 433, hasMore: false, loadingMore: false),
      selectedFolder: 'entities',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('FolderRail groups the seven folders by pipeline stage, marking the three review folders', (
    tester,
  ) async {
    await _render(
      tester,
      const SizedBox(width: 220, height: 900, child: FolderRail()),
      const Size(220, 900),
      folders: folders,
      images: LibraryImagesState.empty,
      selectedFolder: 'scrape_queued',
    );
    expect(tester.takeException(), isNull);
    expect(find.text('INTAKE'), findsOneWidget);
    expect(find.text('SCANNING'), findsOneWidget);
    expect(find.text('YOUR REVIEW'), findsOneWidget);
    expect(find.text('QUEUED'), findsOneWidget);
    // One ⚑ marks the review group's header, not each of its folders.
    expect(find.byIcon(AppIcons.review(_iconWeight)), findsOneWidget);
  });

  testWidgets('LibraryToolbar keeps Apply/Delete visible but disabled with nothing selected', (tester) async {
    await _render(
      tester,
      SizedBox(width: 700, child: LibraryToolbar(folder: 'scrape_queued', entity: null)),
      const Size(700, 200),
      folders: folders,
      images: const LibraryImagesState(images: [], total: 0, hasMore: false, loadingMore: false),
      selectedFolder: 'scrape_queued',
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Delete')).onPressed, isNull);
  });

  testWidgets('LibraryToolbar enables Apply/Delete once something is selected', (tester) async {
    final selectedImages = [_image('a.jpg'), _image('b.jpg')];
    await _render(
      tester,
      SizedBox(width: 700, child: LibraryToolbar(folder: 'scrape_queued', entity: null)),
      const Size(700, 200),
      folders: folders,
      images: LibraryImagesState(images: selectedImages, total: 2, hasMore: false, loadingMore: false),
      selectedFolder: 'scrape_queued',
      selection: const LibrarySelectionState(selected: {'a.jpg', 'b.jpg'}),
    );
    expect(tester.takeException(), isNull);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply')).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Delete')).onPressed, isNotNull);
  });

  testWidgets('LibraryGrid cells match a row-crop folder\'s real shape: wide, short cells', (tester) async {
    await _render(
      tester,
      SizedBox(width: 1024, height: 700, child: LibraryGrid(entityLabel: 'someone', onDeleteRequested: () {})),
      const Size(1024, 700),
      folders: folders,
      images: LibraryImagesState(images: [_image('a.jpg')], total: 1, hasMore: false, loadingMore: false),
      selectedFolder: 'scrape_queued',
      selectedEntity: 'someone',
    );
    expect(tester.takeException(), isNull);
    final stripSize = tester.getSize(find.byType(LibraryTile).first);
    expect(stripSize.width, greaterThan(stripSize.height), reason: 'scrape_queued is a 5.45:1 row-crop shape');
  });

  testWidgets('LibraryGrid cells match a full-page folder\'s real shape: narrow, tall cells', (tester) async {
    await _render(
      tester,
      SizedBox(width: 1024, height: 700, child: LibraryGrid(entityLabel: null, onDeleteRequested: () {})),
      const Size(1024, 700),
      folders: folders,
      images: LibraryImagesState(images: [_image('b.jpg', folder: 'entities', entity: '')], total: 1, hasMore: false, loadingMore: false),
      selectedFolder: 'entities',
    );
    expect(tester.takeException(), isNull);
    final portraitSize = tester.getSize(find.byType(LibraryTile).first);
    expect(portraitSize.height, greaterThan(portraitSize.width), reason: 'entities is a 1:2.08 portrait shape');
  });
}
