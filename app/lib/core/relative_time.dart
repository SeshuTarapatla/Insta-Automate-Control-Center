/// "3m ago" style formatting, shared by the paired-device list (last seen)
/// and the notification center (received). Deliberately coarse — nothing
/// here needs second-level precision once it's more than a minute old.
String relativeTime(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inSeconds < 5) return 'just now';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
}
