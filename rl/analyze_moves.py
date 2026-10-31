"""What the person really does, from the app's move log (dev mode, copy icon).

    uv run python analyze_moves.py data/moves.jsonl [--since 2026-10-31T22:00]

Rebuilds each logged state, asks the simulated players what they would have
done, and summarizes the decisions that distinguish players: hinting versus
discarding at each hint count, plays of uncertain cards, and which card gets
discarded. The numbers feed the "human" ExpertPlayer settings.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict

from hanabi.game import PILES, Card, Fireworks, Game, PlayerView, PLAYERS

SYMBOLS = "RGBYW*"


def build(entry: dict) -> Game:
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
    kind, *rest = text.split()
    return kind, int(rest[0]) if rest else -1


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
        if e["at"] >= args.since:
            entries.append(e)

    games = 0
    scores: list[int] = []
    for k, e in enumerate(entries):
        if e["deck"] == 50 and e["hints"] == 10 and not e["discarded"] and not any(e["piles"]):
            games += 1
            if k:
                scores.append(sum(entries[k - 1]["piles"]))
    if entries:
        scores.append(sum(entries[-1]["piles"]))  # the last game, maybe unfinished
    print(f"{len(entries)} moves, {games} games, final piles summed: {scores}\n")

    by_hints: dict[int, Counter] = defaultdict(Counter)
    sure_play = Counter()
    risky_plays: list[tuple[float, bool, int]] = []
    discards = Counter()
    discard_risk: list[float] = []
    agree = Counter()
    total = 0
    advice_agree = Counter()

    for e in entries:
        game = build(e)
        kind, index = parse_move(e["move"])
        view = PlayerView(game)
        n = len(game.hand)
        sure = [i for i in range(n) if view.surely_playable(i)]
        useless = [i for i in range(n) if view.surely_useless(i)]
        total += 1

        for name in ("expert", "human"):
            move = PLAYERS[name](game)
            if move[0] == kind and (kind == "hint" or move[1] == index):
                agree[name] += 1
        if "advice" in e:
            advice_agree["total"] += 1
            if e["advice"] == e["move"]:
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
