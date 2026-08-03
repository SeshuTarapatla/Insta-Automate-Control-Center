/// CP 7.2 — library-wide views. **Corrected per D75**: the per-entity `user`
/// table row count is not "real scraped profiles" — `profile_scrape` writes
/// that row before its own skip checks, so it counts every attempt, not just
/// the ones that produced an image. `FunnelSummary.scraped`/`.followed` are
/// therefore real all-time totals summed from the `Scrape`/`Follow` daily
/// counters (the same accurate source `Burndown` reads), entirely
/// independent of the per-entity data — not an estimate, not derived from
/// `EntityRanking`. `EntityRanking` itself carries no scraped/followed
/// column at all: there is no accurate *per-entity* source for either
/// number today (the day-counters have no entity attached), so neither is
/// shown there rather than showing something misleading. The Library
/// screen's own per-entity funnel dialog (`EntityYield`, CP 5.4) is
/// unrelated and unchanged — it still shows its own already-documented
/// `followedEst` approximation for one entity at a time.
library;

/// `GET /api/insights/funnel` — whole-library totals.
class FunnelSummary {
  const FunnelSummary({
    required this.entities,
    required this.scanned,
    required this.private,
    required this.female,
    required this.male,
    required this.scraped,
    required this.followed,
  });

  final int entities;
  final int scanned;
  final int private;
  final int female;
  final int male;
  final int scraped;
  final int followed;

  factory FunnelSummary.fromJson(Map<String, dynamic> json) => FunnelSummary(
    entities: json['entities'] as int,
    scanned: json['scanned'] as int,
    private: json['private'] as int,
    female: json['female'] as int,
    male: json['male'] as int,
    scraped: json['scraped'] as int,
    followed: json['followed'] as int,
  );
}

/// `GET /api/insights/ranking` — one row per entity with real scan activity.
/// `scanned`/`private`/`female`/`male` only — all real per-entity Postgres
/// counts from the `scanned` table.
class EntityRanking {
  const EntityRanking({
    required this.root,
    required this.url,
    required this.type,
    required this.access,
    required this.status,
    required this.scanned,
    required this.private,
    required this.female,
    required this.male,
  });

  final String root;
  final String url;
  final String type;
  final String access;
  final String status;
  final int scanned;
  final int private;
  final int female;
  final int male;

  factory EntityRanking.fromJson(Map<String, dynamic> json) => EntityRanking(
    root: json['root'] as String,
    url: json['url'] as String,
    type: json['type'] as String,
    access: json['access'] as String,
    status: json['status'] as String,
    scanned: json['scanned'] as int,
    private: json['private'] as int,
    female: json['female'] as int,
    male: json['male'] as int,
  );
}

/// One day's real count for a burn-down series — `date` stays a plain
/// `YYYY-MM-DD` string (never parsed to `DateTime`) since it is only ever
/// used as a chart x-axis label, not a computed instant.
class BurndownDay {
  const BurndownDay({required this.date, required this.values});

  final String date;
  final Map<String, int> values;

  factory BurndownDay.fromJson(Map<String, dynamic> json) {
    final values = <String, int>{};
    for (final entry in json.entries) {
      if (entry.key != 'date') values[entry.key] = entry.value as int;
    }
    return BurndownDay(date: json['date'] as String, values: values);
  }
}

/// `GET /api/insights/burndown?days=` — real multi-day history for the three
/// day-capped flows, plus each cap's *current* value (there is no historical
/// record of what a limit used to be, only what it is now).
class Burndown {
  const Burndown({
    required this.days,
    required this.limits,
    required this.scan,
    required this.scrape,
    required this.follow,
  });

  final int days;
  final Map<String, int?> limits;
  final List<BurndownDay> scan;
  final List<BurndownDay> scrape;
  final List<BurndownDay> follow;

  factory Burndown.fromJson(Map<String, dynamic> json) {
    final rawLimits = json['limits'] as Map<String, dynamic>;
    return Burndown(
      days: json['days'] as int,
      limits: rawLimits.map((key, value) => MapEntry(key, value as int?)),
      scan: [for (final day in json['scan'] as List) BurndownDay.fromJson(day as Map<String, dynamic>)],
      scrape: [for (final day in json['scrape'] as List) BurndownDay.fromJson(day as Map<String, dynamic>)],
      follow: [for (final day in json['follow'] as List) BurndownDay.fromJson(day as Map<String, dynamic>)],
    );
  }
}
