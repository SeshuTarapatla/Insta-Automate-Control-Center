/// One entity in the shared ENTITY_QUEUE ordering (DECISIONS D8), with what it
/// actually has waiting in each stage directory.
class QueueEntry {
  const QueueEntry({
    required this.name,
    required this.queued,
    required this.scrapeCount,
    required this.followCount,
    required this.hasEntityImage,
  });

  final String name;
  final bool queued;
  final int scrapeCount;
  final int followCount;
  final bool hasEntityImage;

  int get totalCount => scrapeCount + followCount;

  factory QueueEntry.fromJson(Map<String, dynamic> json) => QueueEntry(
    name: json['name'] as String,
    queued: json['queued'] as bool,
    scrapeCount: json['scrape_count'] as int,
    followCount: json['follow_count'] as int,
    hasEntityImage: json['has_entity_image'] as bool,
  );
}

class QueueData {
  const QueueData({required this.queued, required this.unqueued});

  final List<QueueEntry> queued;
  final List<QueueEntry> unqueued;

  factory QueueData.fromJson(Map<String, dynamic> json) => QueueData(
    queued: (json['queued'] as List)
        .map((e) => QueueEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    unqueued: (json['unqueued'] as List)
        .map((e) => QueueEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
