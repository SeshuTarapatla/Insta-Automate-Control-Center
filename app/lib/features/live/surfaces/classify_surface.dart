import 'package:flutter/material.dart';

import '../../../core/agent_image.dart';
import '../../../core/flow_event_models.dart';
import 'surface_common.dart';

/// entity-classify: a verdict card stream (`classify.access`/`classify.gender`)
/// with a running img/s rate — the row-crop aspect ratio matches
/// ARCHITECTURE §5.1's `scanned/<root>/<user>.jpg` shape.
class ClassifySurface extends StatefulWidget {
  const ClassifySurface({super.key, required this.events});

  final List<FlowEvent> events;

  @override
  State<ClassifySurface> createState() => _ClassifySurfaceState();
}

class _ClassifySurfaceState extends State<ClassifySurface> {
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verdicts = widget.events.where((e) => e.kind == 'classify.access' || e.kind == 'classify.gender').toList();
    if (verdicts.isEmpty) {
      return const SurfaceEmpty(message: 'No verdicts yet for this run.');
    }

    final rate = _rate(verdicts);

    // Unlike scan (newest pinned at the top, no scrolling) — classify
    // streams fast enough that oldest-at-top/scroll-to-follow-the-newest
    // reads more naturally here, matching this surface's original design.
    if (verdicts.length != _lastCount) {
      _lastCount = verdicts.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text('${verdicts.length} classified', style: theme.textTheme.titleMedium),
              const SizedBox(width: 10),
              if (rate != null)
                Chip(label: Text('${rate.toStringAsFixed(1)} img/s'), visualDensity: VisualDensity.compact),
            ],
          ),
        ),
        Expanded(
          // Single full-width column (D67's layout fix, kept) — oldest at
          // the top, auto-scrolling to the newest at the bottom (reverted
          // from a same-session mistake that copied scan's newest-at-top
          // pattern here too, which wasn't asked for and read wrong for
          // this surface's faster streaming pace).
          child: ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: verdicts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final event = verdicts[index];
              return ResultCardActions(
                subject: event.subject,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AgentImage(imageKey: event.imageKey, width: 400, aspectRatio: 1080 / 198),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '@${event.subject ?? '?'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            OutcomeBadge(label: event.verdict ?? '?', tone: toneFor(event.verdict)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  double? _rate(List<FlowEvent> verdicts) {
    if (verdicts.length < 2) return null;
    final first = verdicts.first.ts;
    final last = verdicts.last.ts;
    if (first is! num || last is! num) return null;
    final seconds = last - first;
    if (seconds <= 0) return null;
    return verdicts.length / seconds;
  }
}
