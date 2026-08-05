/// One of the seven `IA_DIR` pipeline stage folders (ARCHITECTURE §1.1),
/// with its cached counts.
class LibraryFolderInfo {
  const LibraryFolderInfo({
    required this.name,
    required this.flat,
    required this.total,
    required this.entities,
  });

  final String name;
  final bool flat;
  final int total;
  final int entities;

  factory LibraryFolderInfo.fromJson(Map<String, dynamic> json) => LibraryFolderInfo(
    name: json['name'] as String,
    flat: json['flat'] as bool,
    total: json['total'] as int,
    entities: json['entities'] as int,
  );
}

/// SCREENS.md §5a-0 — the highest-impact single fix in the Library, found by
/// observation, not visible in source: the grid rendered every folder at a
/// near-square cell despite the seven folders holding two very different
/// real image shapes (CLAUDE.md's `IA_DIR` table). `childAspectRatio` is
/// width/height, so a portrait page (narrower than tall) is `< 1` and a row
/// crop (much wider than tall) is `> 1`.
///
/// `entities`/`scraped`/`follow_queued` hold the full profile-page/composite
/// shape (1080×2246, ~1080×2000) — portrait, ~1:2.08. `scanned`/
/// `gender_valid`/`gender_invalid`/`scrape_queued` hold the 1080×198 row-crop
/// shape — a 5.45:1 strip. Matching the cell to the content (instead of a
/// near-square default) turns ~9 visible cells into ~40 in a strip folder at
/// the same grid area — real review throughput, not just a cosmetic fix.
const libraryFolderAspectRatio = {
  'entities': 1 / 2.08,
  'scraped': 1 / 2.08,
  'follow_queued': 1 / 2.08,
  'scanned': 5.45,
  'gender_valid': 5.45,
  'gender_invalid': 5.45,
  'scrape_queued': 5.45,
};

double libraryAspectRatioFor(String? folder) => libraryFolderAspectRatio[folder] ?? 1.0;

/// SCREENS.md §5a — the folder rail grouped by pipeline stage rather than
/// seven undifferentiated rows, so it's visible at a glance which two
/// folders are actually the user's job (⚑) versus just pipeline state.
class LibraryStageGroup {
  const LibraryStageGroup({required this.label, required this.folders, this.review = false});

  final String label;
  final List<String> folders;

  /// True for the two human-in-the-loop folders (`gender_valid`, `scraped`)
  /// — ARCHITECTURE §9's "two humans-in-the-loop steps," the pipeline's
  /// actual bottleneck.
  final bool review;
}

const libraryStageGroups = [
  LibraryStageGroup(label: 'INTAKE', folders: ['entities']),
  LibraryStageGroup(label: 'SCANNING', folders: ['scanned', 'gender_invalid']),
  LibraryStageGroup(label: 'YOUR REVIEW', folders: ['gender_valid', 'scraped'], review: true),
  LibraryStageGroup(label: 'QUEUED', folders: ['scrape_queued', 'follow_queued']),
];

/// One entity root inside a non-flat folder.
class LibraryEntityInfo {
  const LibraryEntityInfo({required this.root, required this.count});

  final String root;
  final int count;

  factory LibraryEntityInfo.fromJson(Map<String, dynamic> json) =>
      LibraryEntityInfo(root: json['root'] as String, count: json['count'] as int);
}

/// One image file — `path` is `IA_DIR`-relative, the addressing scheme every
/// `/api/library/image*` and mutation endpoint takes.
class LibraryImageEntry {
  const LibraryImageEntry({required this.name, required this.path});

  final String name;
  final String path;

  factory LibraryImageEntry.fromJson(Map<String, dynamic> json) =>
      LibraryImageEntry(name: json['name'] as String, path: json['path'] as String);
}

class LibraryImagesPage {
  const LibraryImagesPage({required this.total, required this.offset, required this.images});

  final int total;
  final int offset;
  final List<LibraryImageEntry> images;

  factory LibraryImagesPage.fromJson(Map<String, dynamic> json) => LibraryImagesPage(
    total: json['total'] as int,
    offset: json['offset'] as int,
    images: (json['images'] as List)
        .map((e) => LibraryImageEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// Result of `POST /api/library/apply` — names, not paths, since it's always
/// scoped to the one `(folder, entity)` directory the caller was reviewing.
class ApplyResult {
  const ApplyResult({
    required this.target,
    required this.moved,
    required this.trashed,
    required this.errors,
  });

  final String target;
  final List<String> moved;
  final List<String> trashed;
  final List<String> errors;

  factory ApplyResult.fromJson(Map<String, dynamic> json) => ApplyResult(
    target: json['target'] as String,
    moved: (json['moved'] as List).cast<String>(),
    trashed: (json['trashed'] as List).cast<String>(),
    errors: (json['errors'] as List).cast<String>(),
  );
}

/// Result of `POST /api/library/delete` — paths, since delete can span more
/// than one folder/entity in a single call.
class DeleteResult {
  const DeleteResult({required this.deleted, required this.errors});

  final List<String> deleted;
  final List<String> errors;

  factory DeleteResult.fromJson(Map<String, dynamic> json) => DeleteResult(
    deleted: (json['deleted'] as List).cast<String>(),
    errors: (json['errors'] as List).cast<String>(),
  );
}
