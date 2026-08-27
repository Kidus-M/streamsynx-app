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

  test('tokens match the web palette', () {
    expect(AppColors.bg.toARGB32(), 0xFF0B0B0E);
    expect(AppColors.accent.toARGB32(), 0xFFE9B949);
  });
}
