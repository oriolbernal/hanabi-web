import 'dart:math';

import '../game/card.dart';
import '../game/coop.dart';
import '../game/game.dart';
import 'coop_bot.dart';
import 'expert.dart';
import 'simulated_player.dart';

/// Anything that chooses the current player's move.
typedef CoopPolicy = CoopMove Function(CoopGame game);

/// A partner who plays by the convention most people use without being
/// told: a hint means "play this card" (its [ReceivedHint.focus]), unless
/// it can only be a warning. Built on [base] for everything else.
///
/// - Reading: plays the focus of the last hint received, unless it surely
///   cannot fit, or it is a 5 hint (a save), or one more misfire would end
///   the game and the card is less than [lastLifeChance] likely to fit.
/// - Giving ([givesPlayClues]): hints a card that fits right now so that it
///   is the focus of the hint, to the player who plays soonest; among
///   several, the one touching fewest cards. People rarely give the
///   "informational" hints a probability-minded player gives.
class ClueReader {
  const ClueReader({
    this.base = const CoopBot(player: ExpertPlayer.human, person: null),
    this.givesPlayClues = true,
    this.lastLifeChance = 0.5,
  });

  final CoopBot base;
  final bool givesPlayClues;
  final double lastLifeChance;

  CoopMove decide(CoopGame game) {
    final me = game.current;
    final view = PlayerView(game.viewFor(me));
    // Sure plays first, as anyone would.
    for (var i = 0; i < game.hands[me].length; i++) {
      if (view.surelyPlayable(i)) return _play(game, i);
    }
    final got = game.received[me];
    if (got != null && got.hint != NumberHint(5)) {
      final f = got.focus;
      if (f < game.hands[me].length && !view.surelyUseless(f)) {
        final p = view.playProbability(f);
        if (p > 0 && (game.errors > 1 || p >= lastLifeChance)) {
          return _play(game, f);
        }
      }
    }
    if (givesPlayClues && game.hints > 0) {
      final clue = playClue(game);
      if (clue != null) return clue;
    }
    return base.decide(game);
  }

  CoopMove _play(CoopGame game, int index) => CoopPlay(
    index,
    target: game.needsTarget(index) ? _pile(game, index) : null,
  );

  CardColor? _pile(CoopGame game, int index) {
    final f = game.fireworks;
    final card = game.hands[game.current][index];
    final number = card.knownNumber ? card.number : 2;
    for (final c in CardColor.piles) {
      if ((f.top(c)?.number ?? 0) == number - 1) return c;
    }
    return CardColor.piles.first;
  }

  /// A hint whose focus is a card that fits now and that its holder does
  /// not know yet, for the player who plays soonest.
  static CoopHint? playClue(CoopGame game) {
    final fits = game.fireworks.playableCards();
    for (var k = 1; k < game.players; k++) {
      final to = (game.current + k) % game.players;
      final hand = game.hands[to];
      final chop = hand.indexWhere((c) => !c.knownNumber && !c.knownColor);
      CoopHint? best;
      var fewest = 99;
      for (final hint in game.hintsFor(to)) {
        final touched = [
          for (var i = 0; i < hand.length; i++)
            if (switch (hint) {
              NumberHint(:final number) => hand[i].number == number,
              ColorHint(:final color) => hand[i].color == color,
            })
              i,
        ];
        if (touched.isEmpty) continue;
        final focus = ReceivedHint(game.current, hint, touched, chop).focus;
        final card = hand[focus];
        if (card.knownNumber && card.knownColor) continue;
        if (!fits.any(card.sameAs)) continue;
        if (hint == NumberHint(5)) continue;
        if (touched.length < fewest) {
          fewest = touched.length;
          best = CoopHint(to, hint);
        }
      }
      if (best != null) return best;
    }
    return null;
  }
}

/// Makes a random legal move [chance] of the time, as a distracted person
/// would; otherwise plays like [policy].
class Noisy {
  Noisy(this.policy, {this.chance = 0.1, Random? random})
    : _random = random ?? Random();

  final CoopPolicy policy;
  final double chance;
  final Random _random;

  CoopMove decide(CoopGame game) {
    if (_random.nextDouble() >= chance) return policy(game);
    final me = game.current;
    final options = <CoopMove>[
      for (var i = 0; i < game.hands[me].length; i++) ...[
        CoopDiscard(i),
        if (!game.needsTarget(i)) CoopPlay(i),
      ],
      if (game.hints > 0)
        for (var to = 0; to < game.players; to++)
          if (to != me)
            for (final h in game.hintsFor(to)) CoopHint(to, h),
    ];
    // A discard with every token in hand is wasted but legal.
    return options[_random.nextInt(options.length)];
  }
}

/// The partners bots train and are judged with, by name. Training uses
/// [trainPartners]; [heldOutPartners] are never trained with, to tell a
/// bot that plays well with people from one that learned its partners.
class PartnerZoo {
  PartnerZoo._();

  static ExpertPlayer _human({double play = 0.7}) => ExpertPlayer(
    playThreshold: play,
    hintedPenalty: 0.3,
    reserve: 1,
    lowRisk: 0.15,
    chopDiscards: true,
    jokerNeedsNumber: true,
    name: 'human',
  );

  static CoopPolicy byName(String name, {Random? random}) => switch (name) {
    // Reads hints as information only: the old model of the person.
    'literal' => const CoopBot(player: ExpertPlayer.human, person: null).decide,
    'literal-careful' => CoopBot(
      player: _human(play: 0.95),
      person: null,
    ).decide,
    'literal-bold' => CoopBot(player: _human(play: 0.5), person: null).decide,
    // Reads hints as "play this", gives only information hints.
    'reader' => const ClueReader(givesPlayClues: false).decide,
    // Reads and gives play clues: the closest to most people.
    'clue' => const ClueReader().decide,
    'clue-noisy' => Noisy(const ClueReader().decide, random: random).decide,
    'rules' => const CoopBot(person: null).decide,
    // Held out.
    'clue-bold' => ClueReader(
      base: CoopBot(player: _human(play: 0.5), person: null),
    ).decide,
    'literal-noisy' => Noisy(
      const CoopBot(player: ExpertPlayer.human, person: null).decide,
      chance: 0.15,
      random: random,
    ).decide,
    _ => throw ArgumentError('no partner $name'),
  };

  static const trainPartners = [
    'literal',
    'literal-careful',
    'literal-bold',
    'reader',
    'clue',
    'clue-noisy',
    'rules',
  ];

  static const heldOutPartners = ['clue-bold', 'literal-noisy'];
}
