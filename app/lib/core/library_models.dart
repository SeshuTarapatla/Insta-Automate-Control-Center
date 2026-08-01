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
