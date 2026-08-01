import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library_models.dart';
import 'library_controller.dart';

/// Left column: the seven stage folders with their cached counts.
class FolderRail extends ConsumerWidget {
  const FolderRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(libraryFoldersControllerProvider);
    final selected = ref.watch(selectedFolderProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (folders) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          return _FolderTile(
            folder: folder,
            selected: folder.name == selected,
            onTap: () {
              ref.read(selectedFolderProvider.notifier).select(folder.name);
              ref.read(selectedEntityProvider.notifier).select(null);
            },
          );
        },
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.selected, required this.onTap});

  final LibraryFolderInfo folder;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      title: Text(folder.name, style: theme.textTheme.bodyLarge),
      subtitle: Text(
        folder.flat ? '${folder.total} image(s)' : '${folder.total} across ${folder.entities} entit${folder.entities == 1 ? 'y' : 'ies'}',
        style: theme.textTheme.bodySmall,
      ),
      onTap: onTap,
    );
  }
}

/// Middle column, only shown for non-flat folders: which entity root to view.
class EntityList extends ConsumerStatefulWidget {
  const EntityList({super.key});

  @override
  ConsumerState<EntityList> createState() => _EntityListState();
}

class _EntityListState extends ConsumerState<EntityList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(libraryEntitiesControllerProvider);
    final selected = ref.watch(selectedEntityProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Filter entities',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('$error')),
            data: (entities) {
              final query = _search.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? entities
                  : entities.where((e) => e.root.toLowerCase().contains(query)).toList();
              if (filtered.isEmpty) {
                return const Center(child: Text('No entities here.'));
              }
              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final entity = filtered[index];
                  return ListTile(
                    dense: true,
                    selected: entity.root == selected,
                    title: Text(entity.root, overflow: TextOverflow.ellipsis),
                    trailing: Text('${entity.count}', style: Theme.of(context).textTheme.bodySmall),
                    onTap: () => ref.read(selectedEntityProvider.notifier).select(entity.root),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
