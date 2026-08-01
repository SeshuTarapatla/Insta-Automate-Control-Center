/// Resolves the Instagram URL for an entity id or a scanned/scraped filename
/// (same thing minus `.jpg`) — mirrors `insta_automate.controllers.instagram
/// .Insta.url()` and the mobile app's own `instagramUri()`
/// (`ia_manager/lib/utils/instagram_url.dart`), so the three agree.
///
///   reel-{code} → https://www.instagram.com/reel/{code}
///   post-{code} → https://www.instagram.com/p/{code}
///   anything else → https://www.instagram.com/{value} (a plain account)
///
/// Only the flat `entities` folder's filenames are ever `reel-`/`post-`
/// prefixed (they're Entity ids); every other folder's filenames are
/// discovered usernames, always accounts — this still resolves them
/// correctly since they just fall through to the account case.
Uri instagramUrl(String idOrFilename) {
  final id = idOrFilename.endsWith('.jpg')
      ? idOrFilename.substring(0, idOrFilename.length - 4)
      : idOrFilename;

  if (id.startsWith('reel-')) {
    return Uri.parse('https://www.instagram.com/reel/${id.substring(5)}');
  }
  if (id.startsWith('post-')) {
    return Uri.parse('https://www.instagram.com/p/${id.substring(5)}');
  }
  return Uri.parse('https://www.instagram.com/$id');
}
