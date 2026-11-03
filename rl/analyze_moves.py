"""What the person really does, from the app's move log (dev mode, copy icon).

    uv run python analyze_moves.py data/moves.jsonl [--since 2026-10-31T22:00]

The log has one JSON line per game: the deck in the order it was dealt and
the moves (`p3`, `p3B` for a joker onto the blue pile, `d0`, `h5`, `hR`),
with the advisor's suggestion for each move when it was showing. The older
format, one line per move with the whole visible state, is still read.

Each state is rebuilt, the simulated players are asked what they would have
done, and the decisions that distinguish players are summarized: hinting
versus discarding at each hint count, plays of uncertain cards, and which
card gets discarded. The numbers feed the "human" ExpertPlayer settings.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from dataclasses import dataclass

from hanabi.game import PILES, Card, Fireworks, Game, PlayerView, PLAYERS

SYMBOLS = "RGBYW*"


@dataclass
class Decision:
    """One state the person saw and what they did there."""

    game: Game
    kind: str  # play, discard, hint
    index: int
    advice: tuple[str, int] | None


def build(entry: dict) -> Game:
    """A game in the state an old-format line describes."""
    g = Game.__new__(Game)
    g.deck = [Card(1, 0) for _ in range(entry["deck"])]
    g.hand = [
        Card(
            int(h["card"][0]),
            SYMBOLS.index(h["card"][1]),
            h["knownNumber"],
            h["knownColor"],
            set(h["notNumbers"]),
            {SYMBOLS.index(c) for c in h["notColors"]},
        )
        for h in entry["hand"]
    ]
    g.discarded = [Card(int(s[0]), SYMBOLS.index(s[1])) for s in entry["discarded"]]
    g.fireworks = Fireworks()
    for i, color in enumerate(PILES):
        g.fireworks.piles[color] = [Card(n, color) for n in range(1, entry["piles"][i] + 1)]
    g.hints = entry["hints"]
    g.errors = entry["lives"]
    return g


def parse_move(text: str) -> tuple[str, int]:
    """Both spellings: 'play 3' / 'hint' and 'p3' / 'd0' / 'h5' / 'hR'."""
    if " " in text or text == "hint":
        kind, *rest = text.split()
        return kind, int(rest[0]) if rest else -1
    kind = {"p": "play", "d": "discard", "h": "hint"}[text[0]]
    if kind == "hint":
        return kind, -1
    return kind, int(text[1])


def apply(game: Game, text: str) -> None:
    """Replays one compact move on the game."""
    kind, index = parse_move(text)
    if kind == "hint":
        game.hints -= 1
        value = text[1:]
        if value.isdigit():
            game.apply_hint(("n", int(value)))
        elif value:
            game.apply_hint(("c", SYMBOLS.index(value)))
    elif kind == "play":
        target = SYMBOLS.index(text[2]) if len(text) > 2 else None
        game.play(index, target=target)
    else:
        game.discard(index)


def decisions(entries: list[dict]) -> tuple[list[Decision], list[int]]:
    """Every decision in the log, and the final score of each game."""
    result: list[Decision] = []
    scores: list[int] = []
    old_game_open = False
    for k, e in enumerate(entries):
        if "deck" in e and isinstance(e["deck"], str):
            cards = [Card(int(e["deck"][i]), SYMBOLS.index(e["deck"][i + 1]))
                     for i in range(0, len(e["deck"]), 2)]
            game = Game(cards)
            for move, advice in zip(e["moves"], e["advice"]):
                kind, index = parse_move(move)
                result.append(Decision(game.copy(), kind, index, parse_move(advice) if advice else None))
                apply(game, move)
            scores.append(game.score)
            continue
        # Old format: a new game starts with a full deck and all hints.
        if e["deck"] == 50 and e["hints"] == 10 and not e["discarded"] and not any(e["piles"]):
            if old_game_open:
                scores.append(sum(entries[k - 1]["piles"]))
            old_game_open = True
        kind, index = parse_move(e["move"])
        advice = parse_move(e["advice"]) if "advice" in e else None
        result.append(Decision(build(e), kind, index, advice))
        if k + 1 == len(entries) or "deck" in entries[k + 1] and isinstance(entries[k + 1]["deck"], str):
            scores.append(sum(e["piles"]))  # the last old game, maybe unfinished
            old_game_open = False
    return result, scores


def fits(game: Game, card: Card) -> bool:
    return any(card.same_as(p) for p in game.fireworks.playable_cards())


def chop(game: Game) -> int:
    for i, c in enumerate(game.hand):
        if not c.known_number and not c.known_color:
            return i
    return -1


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--since", default="", help="ignore entries before this ISO time")
    args = parser.parse_args()

    entries = []
    for line in open(args.path):
        line = line.strip()
        if not line.endswith("}"):
            continue
        e = json.loads(line)
        # Cooperative games have several hands: see bin/coop_replay.dart.
        if str(e.get("mode", "")).startswith("coop"):
            continue
        if e["at"] >= args.since:
            entries.append(e)

    all_decisions, scores = decisions(entries)
    print(f"{len(all_decisions)} moves, {len(scores)} games, final scores: {scores}\n")

    by_hints: dict[int, Counter] = defaultdict(Counter)
    sure_play = Counter()
    risky_plays: list[tuple[float, bool, int]] = []
    discards = Counter()
    discard_risk: list[float] = []
    agree = Counter()
    total = 0
    advice_agree = Counter()

    for d in all_decisions:
        game, kind, index = d.game, d.kind, d.index
        view = PlayerView(game)
        n = len(game.hand)
        sure = [i for i in range(n) if view.surely_playable(i)]
        useless = [i for i in range(n) if view.surely_useless(i)]
        total += 1

        for name in ("expert", "human"):
            move = PLAYERS[name](game)
            if move[0] == kind and (kind == "hint" or move[1] == index):
                agree[name] += 1
        if d.advice is not None:
            advice_agree["total"] += 1
            if d.advice == (kind, index):
                advice_agree["same"] += 1

        if sure:
            sure_play["states"] += 1
            if kind == "play" and index in sure:
                sure_play["played"] += 1
            elif kind == "play":
                sure_play["played another"] += 1
            else:
                sure_play[kind] += 1
            continue

        # No sure play: the interesting decisions.
        by_hints[game.hints][kind] += 1
        if kind == "play":
            p = view.play_probability(index)
            risky_plays.append((p, fits(game, game.hand[index]), game.errors))
        elif kind == "discard":
            card = game.hand[index]
            if index in useless:
                discards["surely useless"] += 1
            elif index == chop(game):
                discards["oldest untouched (chop)"] += 1
            elif not card.known_number and not card.known_color:
                discards["other untouched"] += 1
            else:
                discards["hinted card"] += 1
            discard_risk.append(view.expected_discard_risk(index))

    print("With a surely playable card:", dict(sure_play))
    print("\nWithout one, by hints left (hint / discard / play):")
    for h in sorted(by_hints):
        c = by_hints[h]
        print(f"  {h:2} hints: {c['hint']:3} / {c['discard']:3} / {c['play']:3}")

    if risky_plays:
        print(f"\nPlays of uncertain cards: {len(risky_plays)}")
        for lo, hi in ((0.0, 0.3), (0.3, 0.5), (0.5, 0.7), (0.7, 0.9), (0.9, 1.01)):
            group = [r for r in risky_plays if lo <= r[0] < hi]
            if group:
                ok = sum(1 for r in group if r[1])
                lives = Counter(r[2] for r in group)
                print(f"  p in [{lo:.1f},{min(hi, 1):.1f}): {len(group):3}, fit {ok:3}, lives {dict(lives)}")

    print("\nWhich card is discarded (no sure play):", dict(discards))
    if discard_risk:
        print(f"  mean expected risk {sum(discard_risk) / len(discard_risk):.2f}")

    print(f"\nSame move as the simulated players, over {total} decisions:")
    for name, k in agree.items():
        print(f"  {name:8} {k / total:.0%}")
    if advice_agree["total"]:
        print(f"  advisor  {advice_agree['same'] / advice_agree['total']:.0%} (where shown)")


if __name__ == "__main__":
    main()
