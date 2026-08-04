import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/feedback.dart';
import '../../ui/icons.dart';
import '../../ui/text.dart';
import 'library_controller.dart';

/// Left column: the seven stage folders with their cached counts.
class FolderRail extends ConsumerWidget {
  const FolderRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(libraryFoldersControllerProvider);
    final selected = ref.watch(selectedFolderProvider);

    return async.stateView(
      onRetry: () => ref.invalidate(libraryFoldersControllerProvider),
      data: (folders) => ListView.builder(
        padding: EdgeInsets.symmetric(vertical: Theme.of(context).tokens.space.sm),
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
      subtitle: NumericText(
        folder.flat ? '${folder.total} image(s)' : '${folder.total} across ${folder.entities} entit${folder.entities == 1 ? 'y' : 'ies'}',
        role: TextRole.caption,
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

    final tokens = Theme.of(context).tokens;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(tokens.space.sm, tokens.space.sm, tokens.space.sm, tokens.space.xs),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: AppIcon(AppIcons.search, size: IconSize.sm),
              hintText: 'Filter entities',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: async.stateView(
            onRetry: () => ref.invalidate(libraryEntitiesControllerProvider),
            data: (entities) {
              final query = _search.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? entities
                  : entities.where((e) => e.root.toLowerCase().contains(query)).toList();
              if (filtered.isEmpty) {
                return const EmptyView(icon: Icons.person_outline, title: 'No entities here');
              }
              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final entity = filtered[index];
                  return ListTile(
                    dense: true,
                    selected: entity.root == selected,
                    title: Text(entity.root, overflow: TextOverflow.ellipsis),
                    trailing: NumericText('${entity.count}', role: TextRole.caption),
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
