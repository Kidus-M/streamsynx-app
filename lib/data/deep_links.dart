import 'models.dart';

/// Links that survive leaving the app.
///
/// A shared poster has to work for two kinds of recipient: someone who already
/// has StreamSynx, and someone who does not. One HTTPS link covers both — Android
/// App Links hand a verified URL straight to the installed app, and everyone else
/// lands on the site's `/open` page, which shows the title and offers the
/// download. That is also why this replaced Firebase Dynamic Links, which Google
/// shut down.
class DeepLinks {
  const DeepLinks._();

  static const site = 'https://streamsynx.vercel.app';

  /// The canonical shareable link for a title.
  static String forItem(MediaItem item) => '$site/open/${item.type}/${item.id}';

  /// The private scheme, used by the `/open` page to try the app first on
  /// platforms where App Links are not verified.
  static String schemeFor(MediaItem item) =>
      'streamsynx://title/${item.type}/${item.id}';

  /// Where to send someone who does not have the app yet.
  static const download = '$site/download';

  /// Parses an incoming link back into something the app can open.
  ///
  /// Accepts both `https://…/open/movie/123` and `streamsynx://title/movie/123`.
  static ({String type, int id})? parse(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    // streamsynx://title/movie/123 puts "title" in the host, not the path.
    final parts = uri.scheme == 'streamsynx'
        ? [uri.host, ...segments]
        : segments;

    final anchor = parts.indexWhere((s) => s == 'open' || s == 'title');
    if (anchor == -1 || parts.length < anchor + 3) return null;

    final type = parts[anchor + 1];
    final id = int.tryParse(parts[anchor + 2]);
    if ((type != 'movie' && type != 'tv') || id == null) return null;

    return (type: type, id: id);
  }

  /// The message a shared link travels as.
  ///
  /// The URL is on its own line and last. Messaging apps unfurl the final link
  /// in a message and only that one, so anything appended after it costs the
  /// preview — which is the whole point of sharing a link rather than a picture.
  static String shareText(MediaItem item) {
    final year = item.year;
    final name = year.isEmpty ? item.title : '${item.title} ($year)';
    return '$name — watch it on StreamSynx\n${forItem(item)}';
  }

  /// The caption that travels alongside a story image, where the link is not
  /// tappable and has to be readable instead.
  static String posterText(MediaItem item) =>
      '${item.title} on StreamSynx · ${forItem(item)}';
}
