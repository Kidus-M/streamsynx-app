import 'package:flutter_test/flutter_test.dart';
import 'package:streamsynx/theme/tokens.dart';
import 'package:streamsynx/data/deep_links.dart';
import 'package:streamsynx/data/models.dart';

void main() {
  group('DeepLinks', () {
    final item = MediaItem(id: 42, type: 'movie', title: 'Test');

    test('builds a shareable https link for a title', () {
      expect(DeepLinks.forItem(item), 'https://streamsynx.vercel.app/open/movie/42');
    });

    test('parses its own https link back', () {
      final parsed = DeepLinks.parse(Uri.parse(DeepLinks.forItem(item)));
      expect(parsed?.type, 'movie');
      expect(parsed?.id, 42);
    });

    test('parses the private scheme, where the anchor sits in the host', () {
      final parsed = DeepLinks.parse(Uri.parse('streamsynx://title/tv/99'));
      expect(parsed?.type, 'tv');
      expect(parsed?.id, 99);
    });

    test('rejects links that are not titles', () {
      expect(DeepLinks.parse(Uri.parse('https://streamsynx.vercel.app/download')), isNull);
      expect(DeepLinks.parse(Uri.parse('https://streamsynx.vercel.app/open/book/1')), isNull);
    });
  });

  group('MediaItem.fromStored', () {
    test('reads a watchlist entry', () {
      final item = MediaItem.fromStored({
        'id': 7,
        'media_type': 'movie',
        'title': 'A Film',
        'poster_path': '/p.jpg',
      });
      expect(item.id, 7);
      expect(item.isTv, isFalse);
      expect(item.title, 'A Film');
    });

    test("reads the website's tv favourite shape", () {
      final item = MediaItem.fromStored({
        'tvShowId': 99,
        'tvShowName': 'A Series',
        'poster_path': '/s.jpg',
        'type': 'tv',
      });
      expect(item.id, 99);
      expect(item.isTv, isTrue);
      expect(item.title, 'A Series');
    });

    test('treats a missing media_type as a film rather than dropping the row', () {
      final item = MediaItem.fromStored({'id': 3, 'title': 'Legacy'});
      expect(item.type, 'movie');
    });
  });

  test('tokens match the web palette', () {
    expect(AppColors.bg.toARGB32(), 0xFF0B0B0E);
    expect(AppColors.accent.toARGB32(), 0xFFE9B949);
  });
}
