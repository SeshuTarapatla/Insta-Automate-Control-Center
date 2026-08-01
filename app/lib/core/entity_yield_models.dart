/// One entity's progress across every pipeline stage (PLAN CP 5.4),
/// `GET /api/library/entity/{root}/yield`. `scanned`/`private`/`female`/
/// `male`/`scraped` are real Postgres counts; `followedEst` is an
/// approximation (`scraped − still in scraped/ − still in follow_queued/`)
/// since no per-entity "followed" record exists anywhere — see
/// `entity_view.py`'s module docstring for why.
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
    required this.scraped,
    required this.inScrapedFolder,
    required this.inFollowQueuedFolder,
    required this.followedEst,
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
  final int scraped;
  final int inScrapedFolder;
  final int inFollowQueuedFolder;
  final int followedEst;

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
    scraped: json['scraped'] as int,
    inScrapedFolder: json['in_scraped_folder'] as int,
    inFollowQueuedFolder: json['in_follow_queued_folder'] as int,
    followedEst: json['followed_est'] as int,
  );
}
