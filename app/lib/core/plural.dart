/// The shared "N thing(s)" formatter — replaces the ad-hoc string surgery
/// each screen was hand-rolling (`'${folder.total} image(s)'`,
/// `'entit${entities == 1 ? 'y' : 'ies'}'`), COMPONENTS.md's `plural()`
/// helper (SCREENS.md §5a).
String plural(int count, String singular, [String? irregularPlural]) =>
    count == 1 ? '$count $singular' : '$count ${irregularPlural ?? '${singular}s'}';
