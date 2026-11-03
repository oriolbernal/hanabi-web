import 'coop_features.dart';
import 'coop_search.dart';
import 'mlp.dart';
import '../game/coop.dart';

/// A co-op bot that scores each candidate move with a network trained on
/// the search's values (`rl/coop_distill.py`) and plays the best one: about
/// as good as the search, many times faster.
class CoopNet {
  CoopNet(Map<String, dynamic> weights)
    : _net = Mlp(weights),
      _search = CoopSearch(rounds: 0) {
    final version = weights['features'];
    if (version != CoopFeatures.version) {
      throw ArgumentError(
        'model for features $version, '
        'not ${CoopFeatures.version}',
      );
    }
  }

  final Mlp _net;

  /// Only used for its list of candidate moves.
  final CoopSearch _search;

  CoopMove decide(CoopGame game) {
    final options = _search.candidates(game);
    if (options.length == 1) {
      return CoopSearch.withTarget(game, options.single);
    }
    final f = CoopFeatures(game);
    var best = options.first;
    var bestScore = double.negativeInfinity;
    for (final m in options) {
      final score = _net([...f.state, ...f.move(m)]).first;
      if (score > bestScore) {
        best = m;
        bestScore = score;
      }
    }
    return CoopSearch.withTarget(game, best);
  }
}
