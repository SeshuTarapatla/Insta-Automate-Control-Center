/// One entity's progress across the scan-side pipeline stages (PLAN CP 5.4,
/// D81-corrected), `GET /api/library/entity/{root}/yield`.
/// `scanned`/`private`/`female`/`male` are real Postgres counts.
///
/// **`scraped`/`followed` are deliberately not here.** The first version
/// counted `user`-table rows as "scraped" and derived a "followed" estimate
/// from that — but `profile_scrape` writes that row before its own skip
/// checks, so it counts every profile read, not just real scrapes (the same
/// bug `insights.py`'s `ranking()` had, D76). Neither number has an accurate
/// per-entity source (the real success signal, `Scrape.scraped`/
/// `Follow.followed`, is a global daily counter with no entity attached), so
/// — matching the Insights Ranking tab's own precedent — this funnel stops
/// at `female` rather than show an inflated or approximated number.
class EntityYield {
  const EntityYield({
    required this.root,
    required this.url,
    required this.type,
    required this.access,
    required this.status,
    required this.addedOn,
    required this.updatedOn,
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
  final DateTime addedOn;
  final DateTime updatedOn;
  final int scanned;
  final int private;
  final int female;
  final int male;

  factory EntityYield.fromJson(Map<String, dynamic> json) => EntityYield(
    root: json['root'] as String,
    url: json['url'] as String,
    type: json['type'] as String,
    access: json['access'] as String,
    status: json['status'] as String,
    addedOn: DateTime.parse(json['added_on'] as String),
    updatedOn: DateTime.parse(json['updated_on'] as String),
    scanned: json['scanned'] as int,
    private: json['private'] as int,
    female: json['female'] as int,
    male: json['male'] as int,
  );
}
