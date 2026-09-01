import 'dart:math' as math;

import 'taste_profile.dart';

/// Taste matching, ported from `stream-sync/lib/tasteMatch.js`.
///
/// Scoring runs over five signals: genres, themes (TMDB keywords), the people
/// behind a title, decades, and a small social nudge for mutual buddies.
///
/// Why rarity weighting matters: almost everyone picks a Drama, and almost
/// everyone has Christopher Nolan somewhere. Weighting each shared trait by how
/// rare it is in the current pool means matches are driven by what actually
/// distinguishes two people, not by what everybody has in common.
class TasteMatch {
  const TasteMatch({
    required this.score,
    required this.tier,
    required this.sharedTitleKeys,
    required this.sharedGenres,
    required this.sharedPeople,
    required this.sharedThemes,
    required this.mutualCount,
  });

  final double score;
  final MatchTier tier;
  final List<String> sharedTitleKeys;
  final List<String> sharedGenres;
  final List<String> sharedPeople;
  final List<String> sharedThemes;
  final int mutualCount;

  int get percent => (score * 100).round();

  /// Sentence fragments a card can show under a match, best signal first.
  List<String> get reasons {
    final out = <String>[];
    if (sharedTitleKeys.isNotEmpty) {
      final n = sharedTitleKeys.length;
      out.add(n == 1 ? 'Picked the same title' : 'Picked $n of the same titles');
    }
    if (sharedGenres.isNotEmpty) out.add('Both into ${_list(sharedGenres)}');
    if (sharedPeople.isNotEmpty) out.add('Both follow ${_list(sharedPeople)}');
    if (sharedThemes.isNotEmpty) out.add('Shared themes: ${_list(sharedThemes)}');
    if (mutualCount > 0) {
      out.add(mutualCount == 1 ? '1 buddy in common' : '$mutualCount buddies in common');
    }
    return out;
  }

  static String _list(List<String> items) {
    final take = items.take(2).toList();
    return take.length == 1 ? take.first : '${take.first} and ${take.last}';
  }
}

class MatchTier {
  const MatchTier(this.min, this.label);

  final double min;
  final String label;
}

class TasteScorer {
  const TasteScorer._();

  /// Relative pull of each facet before missing-facet redistribution.
  static const _facetWeights = <String, double>{
    'genres': 0.46,
    'keywords': 0.24,
    'people': 0.18,
    'decades': 0.12,
  };

  /// How much of the final score mutual buddies can account for.
  static const _socialWeight = 0.06;
  static const _socialSaturation = 3;

  /// Below this, a match is too thin to show.
  static const minScore = 0.28;

  static const _tiers = <MatchTier>[
    MatchTier(0.85, 'Uncanny match'),
    MatchTier(0.7, 'Strong match'),
    MatchTier(0.55, 'Good match'),
    MatchTier(0.4, 'Some overlap'),
    MatchTier(0, 'Loose match'),
  ];

  static MatchTier tierFor(double score) =>
      _tiers.firstWhere((tier) => score >= tier.min, orElse: () => _tiers.last);

  static double _clamp01(double value) => value.clamp(0.0, 1.0);

  // --- Inverse document frequency ---------------------------------------------

  /// Rarity tables built from the candidate pool itself. Using the live pool
  /// rather than a maintained index means no extra writes, and the weights
  /// always describe the population actually being ranked.
  static IdfTables buildIdf(List<TasteProfile> profiles) => IdfTables(
        genres: _idfOver(profiles, (p) => p.genres.keys),
        keywords: _idfOver(profiles, (p) => p.keywords.keys),
        people: _idfOver(profiles, (p) => p.people.keys),
        decades: _idfOver(profiles, (p) => p.decades.keys),
        titles: _idfOver(profiles, (p) => p.titles),
      );

  static Map<String, double> _idfOver(
    List<TasteProfile> profiles,
    Iterable<String> Function(TasteProfile) pick,
  ) {
    final total = profiles.isEmpty ? 1 : profiles.length;
    final frequency = <String, int>{};

    for (final profile in profiles) {
      for (final key in pick(profile).toSet()) {
        frequency[key] = (frequency[key] ?? 0) + 1;
      }
    }

    return {
      for (final entry in frequency.entries)
        entry.key: math.log(1 + total / (1 + entry.value)),
    };
  }

  static double _rarity(Map<String, double>? table, String key) =>
      table?[key] ?? 1;

  // --- Similarity --------------------------------------------------------------

  /// Cosine similarity between two sparse weight maps, each dimension scaled by
  /// its rarity. Re-normalising inside is required: applying rarity to vectors
  /// that were stored unit-length makes them non-unit again.
  static double weightedCosine(
    Map<String, double> a,
    Map<String, double> b,
    Map<String, double>? table,
  ) {
    if (a.isEmpty || b.isEmpty) return 0;

    var product = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;

    a.forEach((key, value) {
      final weight = _rarity(table, key);
      leftNorm += math.pow(value * weight, 2).toDouble();
      final other = b[key];
      if (other != null) product += value * other * weight * weight;
    });

    b.forEach((key, value) {
      final weight = _rarity(table, key);
      rightNorm += math.pow(value * weight, 2).toDouble();
    });

    if (leftNorm == 0 || rightNorm == 0) return 0;
    return _clamp01(product / math.sqrt(leftNorm * rightNorm));
  }

  static List<String> _sharedDimensions(
    Map<String, double> a,
    Map<String, double> b,
    Map<String, double>? table,
    int limit,
  ) {
    final shared = a.keys.where(b.containsKey).map((key) {
      return MapEntry(key, a[key]! * b[key]! * _rarity(table, key));
    }).toList()
      ..sort((x, y) => y.value.compareTo(x.value));

    return shared.take(limit).map((entry) => entry.key).toList(growable: false);
  }

  /// Share of hand-picked titles in common, weighted by rarity. Dividing by the
  /// smaller side keeps it symmetric, so someone with three picks can still
  /// reach 1.0 when all three are shared.
  static ({double ratio, List<String> shared}) _titleOverlap(
    List<String> a,
    List<String> b,
    Map<String, double>? table,
  ) {
    if (a.isEmpty || b.isEmpty) return (ratio: 0.0, shared: const <String>[]);

    final others = b.toSet();
    final shared = a.where(others.contains).toList(growable: false);
    if (shared.isEmpty) return (ratio: 0.0, shared: const <String>[]);

    double mass(List<String> keys) =>
        keys.fold<double>(0, (sum, key) => sum + _rarity(table, key));

    final floor = math.min(mass(a), mass(b));
    return (
      ratio: floor == 0 ? 0.0 : _clamp01(mass(shared) / floor),
      shared: shared,
    );
  }

  /// Someone with two picks has told us far less than someone with eight, so
  /// their scores are pulled toward the middle rather than trusted outright.
  static double _confidence(int count) =>
      0.45 +
      0.55 * (math.min(count, TasteProfile.totalPickSlots) / TasteProfile.totalPickSlots);

  // --- Scoring -----------------------------------------------------------------

  static TasteMatch score(
    TasteProfile mine,
    TasteProfile theirs, {
    IdfTables? idf,
    int mutualCount = 0,
  }) {
    final facets = <String, double>{
      'genres': weightedCosine(mine.genres, theirs.genres, idf?.genres),
      'keywords': weightedCosine(mine.keywords, theirs.keywords, idf?.keywords),
      'people': weightedCosine(mine.people, theirs.people, idf?.people),
      'decades': weightedCosine(mine.decades, theirs.decades, idf?.decades),
    };

    Map<String, double> vectorFor(TasteProfile profile, String facet) => switch (facet) {
          'keywords' => profile.keywords,
          'people' => profile.people,
          'decades' => profile.decades,
          _ => profile.genres,
        };

    // Redistribute the weight of any facet neither side can speak to.
    final active = _facetWeights.keys.where(
      (facet) => vectorFor(mine, facet).isNotEmpty && vectorFor(theirs, facet).isNotEmpty,
    );
    final activeWeight =
        active.fold<double>(0, (sum, facet) => sum + _facetWeights[facet]!);
    final affinity = activeWeight == 0
        ? 0.0
        : active.fold<double>(
            0,
            (sum, facet) => sum + (_facetWeights[facet]! / activeWeight) * facets[facet]!,
          );

    final overlap = _titleOverlap(mine.titles, theirs.titles, idf?.titles);

    // Shared picks lift the pair toward a perfect match from wherever affinity
    // put them — additive would let one shared blockbuster dominate.
    final core = affinity + (1 - affinity) * overlap.ratio;

    // Geometric mean, not a product: two thin profiles should be discounted
    // once for being thin, not squared into irrelevance.
    final confidence =
        math.sqrt(_confidence(mine.pickCount) * _confidence(theirs.pickCount));
    final social = math.min(1.0, mutualCount / _socialSaturation);
    final total = _clamp01(core * confidence * (1 - _socialWeight) + social * _socialWeight);

    String? labelFor(Map<String, String> a, Map<String, String> b, String key) =>
        a[key] ?? b[key];

    return TasteMatch(
      score: total,
      tier: tierFor(total),
      sharedTitleKeys: overlap.shared,
      sharedGenres: _sharedDimensions(mine.genres, theirs.genres, idf?.genres, 3)
          .map(genreNameFor)
          .whereType<String>()
          .toList(growable: false),
      sharedPeople: _sharedDimensions(mine.people, theirs.people, idf?.people, 3)
          .map((key) => labelFor(theirs.peopleLabels, mine.peopleLabels, key))
          .whereType<String>()
          .toList(growable: false),
      sharedThemes: _sharedDimensions(mine.keywords, theirs.keywords, idf?.keywords, 3)
          .map((key) => labelFor(theirs.keywordLabels, mine.keywordLabels, key))
          .whereType<String>()
          .toList(growable: false),
      mutualCount: mutualCount,
    );
  }
}

class IdfTables {
  const IdfTables({
    required this.genres,
    required this.keywords,
    required this.people,
    required this.decades,
    required this.titles,
  });

  final Map<String, double> genres;
  final Map<String, double> keywords;
  final Map<String, double> people;
  final Map<String, double> decades;
  final Map<String, double> titles;
}
