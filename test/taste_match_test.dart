import 'package:flutter_test/flutter_test.dart';
import 'package:streamsynx/data/taste_match.dart';
import 'package:streamsynx/data/taste_profile.dart';

/// Guards the port of the website's scorer. The two clients write to the same
/// `users/{uid}` document, so these behaviours have to hold identically or a
/// profile built on the phone would rank differently on the web.
void main() {
  TasteProfile profile({
    Map<String, double> genres = const {},
    Map<String, double> people = const {},
    List<String> titles = const [],
    int pickCount = 8,
  }) =>
      TasteProfile(
        genres: genres,
        people: people,
        titles: titles,
        pickCount: pickCount,
      );

  group('TasteScorer', () {
    test('identical taste scores far above the display threshold', () {
      final me = profile(genres: {'18': 0.8, '80': 0.6}, titles: ['movie:1', 'movie:2']);
      final match = TasteScorer.score(me, me, idf: TasteScorer.buildIdf([me, me]));

      expect(match.score, greaterThan(0.8));
      expect(match.sharedTitleKeys, hasLength(2));
    });

    test('disjoint taste falls below the threshold', () {
      final me = profile(genres: {'18': 1.0});
      final them = profile(genres: {'16': 1.0});
      final match = TasteScorer.score(me, them, idf: TasteScorer.buildIdf([me, them]));

      expect(match.score, lessThan(TasteScorer.minScore));
    });

    test('a thin profile is discounted rather than trusted outright', () {
      final me = profile(genres: {'18': 1.0}, pickCount: 8);
      final thin = profile(genres: {'18': 1.0}, pickCount: 1);
      final full = profile(genres: {'18': 1.0}, pickCount: 8);

      final idf = TasteScorer.buildIdf([me, thin, full]);
      final thinScore = TasteScorer.score(me, thin, idf: idf).score;
      final fullScore = TasteScorer.score(me, full, idf: idf).score;

      expect(thinScore, lessThan(fullScore));
    });

    test('rarity weighting favours the uncommon trait', () {
      // Everyone shares genre 18; only the pair shares 27.
      final crowd = [
        profile(genres: {'18': 1.0}),
        profile(genres: {'18': 1.0}),
        profile(genres: {'18': 1.0}),
      ];
      final me = profile(genres: {'18': 0.7, '27': 0.7});
      final rare = profile(genres: {'18': 0.7, '27': 0.7});
      final common = profile(genres: {'18': 1.0});

      final idf = TasteScorer.buildIdf([me, rare, common, ...crowd]);
      expect(
        TasteScorer.score(me, rare, idf: idf).score,
        greaterThan(TasteScorer.score(me, common, idf: idf).score),
      );
    });

    test('mutual buddies nudge the score without dominating it', () {
      final me = profile(genres: {'18': 1.0});
      final them = profile(genres: {'18': 1.0});
      final idf = TasteScorer.buildIdf([me, them]);

      final alone = TasteScorer.score(me, them, idf: idf).score;
      final social = TasteScorer.score(me, them, idf: idf, mutualCount: 3).score;

      expect(social, greaterThan(alone));
      expect(social - alone, lessThan(0.07));
    });

    test('tiers are ordered and cover the whole range', () {
      expect(TasteScorer.tierFor(0.9).label, 'Uncanny match');
      expect(TasteScorer.tierFor(0.0).label, 'Loose match');
    });
  });

  group('TastePicks', () {
    test('caps each type at four and toggles off', () {
      var picks = const TastePicks();
      for (var i = 1; i <= 5; i++) {
        picks = picks.toggle(TastePick(id: i, type: 'movie', title: 'Film $i'));
      }
      expect(picks.movies, hasLength(TasteProfile.maxPicksPerType));

      picks = picks.toggle(TastePick(id: 1, type: 'movie', title: 'Film 1'));
      expect(picks.movies, hasLength(3));
      expect(picks.contains(1, 'movie'), isFalse);
    });

    test('films and series have independent slots', () {
      var picks = const TastePicks();
      for (var i = 1; i <= 4; i++) {
        picks = picks.toggle(TastePick(id: i, type: 'movie', title: 'Film $i'));
      }
      picks = picks.toggle(const TastePick(id: 9, type: 'tv', title: 'A Series'));

      expect(picks.movies, hasLength(4));
      expect(picks.shows, hasLength(1));
      expect(picks.count, 5);
    });
  });
}
