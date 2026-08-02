/// Notification messages are built for Telegram's own markdown renderer
/// (`**bold**`, `[text](url)`) — the same string is stored/shown verbatim by
/// the agent, so it needs cleaning up here rather than showing the raw
/// syntax. Deliberately not a general markdown parser and deliberately not
/// styled bold either (confirmed with the user 2026-08-02 — plain text reads
/// better here than bold, matching the mobile client's equivalent stripper):
/// only strips the two forms these messages actually use.
///
/// `[text](url)` is reduced to just `text` — navigation is handled by the
/// notification tile's own `url` field and a whole-tile tap, not an inline
/// clickable span (unreliable to hit-test inside a 3-line ellipsized `Text`).
String stripNotificationMarkdown(String raw) {
  final linkless = raw.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1) ?? '');
  return linkless.replaceAll('**', '');
}
