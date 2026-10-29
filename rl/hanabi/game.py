"""Python port of lib/game and lib/sim/simulated_player.dart.

It must behave exactly like the Dart code: tests/test_parity.py replays games
exported from Dart and checks every decision and final score.
"""

from __future__ import annotations

import random
from dataclasses import dataclass

RED, GREEN, BLUE, YELLOW, WHITE, JOKER = range(6)
COLORS = 6
PILES = (RED, GREEN, BLUE, YELLOW, WHITE)

MAX_HINTS = 10
ALLOWED_ERRORS = 3
HAND_SIZE = 5
NUMBER_DISTRIBUTION = (3, 2, 2, 2, 1)

# A hint is ("n", number) or ("c", color).
Hint = tuple[str, int]


@dataclass
class Card:
    number: int
    color: int
    known_number: bool = False
    known_color: bool = False

    @property
    def is_joker(self) -> bool:
        return self.color == JOKER

    def reveal(self) -> None:
        self.known_number = True
        self.known_color = True

    def same_as(self, other: Card) -> bool:
        return self.number == other.number and self.color == other.color

    def copy(self) -> Card:
        return Card(self.number, self.color, self.known_number, self.known_color)


def copies(number: int, color: int) -> int:
    return 1 if color == JOKER else NUMBER_DISTRIBUTION[number - 1]


def build_deck(rng: random.Random) -> list[Card]:
    cards = [
        Card(n, c)
        for c in PILES
        for n in range(1, 6)
        for _ in range(NUMBER_DISTRIBUTION[n - 1])
    ]
    cards += [Card(n, JOKER) for n in range(1, 6)]
    rng.shuffle(cards)
    return cards


class Fireworks:
    def __init__(self) -> None:
        self.piles: dict[int, list[Card]] = {c: [] for c in PILES}

    def top(self, color: int) -> Card | None:
        p = self.piles[color]
        return p[-1] if p else None

    def top_number(self, color: int) -> int:
        t = self.top(color)
        return t.number if t else 0

    def fits(self, card: Card, color: int) -> bool:
        t = self.top(color)
        return card.number == 1 if t is None else card.number - t.number == 1

    def floating_joker(self) -> int | None:
        for c in PILES:
            p = self.piles[c]
            if len(p) == 1 and p[0].is_joker:
                return c
        return None

    def play(self, card: Card, target: int | None = None) -> bool:
        if card.is_joker:
            if card.number == 1:
                for c in PILES:
                    if not self.piles[c]:
                        self.piles[c].append(card)
                        return True
                return False
            if target is not None and self.fits(card, target):
                self.piles[target].append(card)
                return True
            return False

        if self.fits(card, card.color):
            self.piles[card.color].append(card)
            return True
        return self._play_by_moving_joker(card)

    def _play_by_moving_joker(self, card: Card) -> bool:
        source = self.floating_joker()
        if source is None:
            return False
        joker = self.piles[source][0]
        self.piles[source].clear()
        for c in PILES:
            if self.piles[c]:
                continue
            self.piles[c].append(joker)
            if self.fits(card, card.color):
                self.piles[card.color].append(card)
                return True
            self.piles[c].clear()
        self.piles[source].append(joker)
        return False

    def playable_cards(self) -> list[Card]:
        result = []
        for c in PILES:
            t = self.top(c)
            if t is None:
                result += [Card(1, c), Card(1, JOKER)]
            elif t.number < 5:
                result += [Card(t.number + 1, c), Card(t.number + 1, JOKER)]
        return result

    @property
    def victory(self) -> bool:
        return all(self.top_number(c) == 5 for c in PILES)

    @property
    def score(self) -> int:
        return sum(self.top_number(c) for c in PILES)


class Game:
    def __init__(self, deck: list[Card]) -> None:
        self.deck = deck
        self.hand: list[Card] = []
        self.discarded: list[Card] = []
        self.fireworks = Fireworks()
        self.hints = MAX_HINTS
        self.errors = ALLOWED_ERRORS
        self._draw(HAND_SIZE)

    @property
    def score(self) -> int:
        return self.fireworks.score

    @property
    def is_over(self) -> bool:
        return (
            self.fireworks.victory
            or (not self.deck and not self.hand)
            or self.errors == 0
        )

    def remaining(self, number: int, color: int) -> int:
        gone = sum(1 for c in self.discarded if c.number == number and c.color == color)
        return copies(number, color) - gone

    def needs_target(self, index: int) -> bool:
        card = self.hand[index]
        return card.is_joker and card.number != 1

    def play(self, index: int, target: int | None = None) -> bool:
        card = self.hand.pop(index)
        card.reveal()
        self._draw(1)
        if self.fireworks.play(card, target):
            return True
        self.discarded.append(card)
        self.errors -= 1
        return False

    def discard(self, index: int) -> None:
        card = self.hand.pop(index)
        card.reveal()
        self.discarded.append(card)
        self._draw(1)
        if self.hints < MAX_HINTS:
            self.hints += 1

    def useful_hints(self) -> list[Hint]:
        result: dict[Hint, None] = {}
        for card in self.hand:
            if not card.known_number:
                result[("n", card.number)] = None
            if not card.known_color:
                result[("c", card.color)] = None
        return list(result)

    def apply_hint(self, hint: Hint) -> None:
        kind, value = hint
        for card in self.hand:
            if kind == "n" and card.number == value:
                card.known_number = True
            elif kind == "c" and card.color == value:
                card.known_color = True

    def _draw(self, count: int) -> None:
        for _ in range(count):
            if self.deck:
                self.hand.append(self.deck.pop(0))


def is_dead(game: Game, card: Card) -> bool:
    piles = PILES if card.is_joker else (card.color,)
    return all(game.fireworks.top_number(c) >= card.number for c in piles)


def is_critical(game: Game, card: Card) -> bool:
    return not is_dead(game, card) and game.remaining(card.number, card.color) == 1


def dummy_hint(game: Game) -> Hint | None:
    """The original console rule (DummyStrategy)."""
    playable = game.fireworks.playable_cards()
    scores: dict[Hint, int] = {}
    for card in game.hand:
        is_playable = any(card.same_as(p) for p in playable)
        bumps = 2 if is_playable else 1
        if not card.known_number:
            key = ("n", card.number)
            scores[key] = scores.get(key, 0) + bumps
        if not card.known_color:
            key = ("c", card.color)
            scores[key] = scores.get(key, 0) + bumps
    if not scores:
        return None
    best = None
    for key, value in scores.items():
        if best is None or value > scores[best]:
            best = key
    return best


class PlayerView:
    """What the simulated player can deduce about each card in hand."""

    def __init__(self, game: Game) -> None:
        self.game = game
        self.seen: dict[tuple[int, int], int] = {}
        for c in game.discarded:
            self._see(c)
        for color in PILES:
            for c in game.fireworks.piles[color]:
                self._see(c)

    def _see(self, card: Card) -> None:
        key = (card.number, card.color)
        self.seen[key] = self.seen.get(key, 0) + 1

    def candidates(self, index: int) -> list[tuple[int, int]]:
        card = self.game.hand[index]
        colors = [card.color] if card.known_color else range(COLORS)
        numbers = [card.number] if card.known_number else range(1, 6)
        return [
            (n, c)
            for c in colors
            for n in numbers
            if self.seen.get((n, c), 0) < copies(n, c)
        ]

    def _can_play(self, number: int, color: int) -> bool:
        f = self.game.fireworks
        probe = Card(number, color)
        if color != JOKER:
            return f.fits(probe, color)
        return any(f.fits(probe, c) for c in PILES)

    def _is_dead(self, number: int, color: int) -> bool:
        f = self.game.fireworks
        piles = PILES if color == JOKER else (color,)
        return all(f.top_number(c) >= number for c in piles)

    def surely_playable(self, index: int) -> bool:
        options = self.candidates(index)
        return bool(options) and all(self._can_play(n, c) for n, c in options)

    def surely_useless(self, index: int) -> bool:
        options = self.candidates(index)
        return bool(options) and all(self._is_dead(n, c) for n, c in options)

    def maybe_valuable(self, index: int) -> bool:
        card = self.game.hand[index]
        return (card.known_number and card.number == 5) or (
            card.known_color and card.is_joker
        )


# Moves of the careful player: ("play", i), ("discard", i) or ("hint", -1).
Move = tuple[str, int]


def careful_move(game: Game) -> Move:
    view = PlayerView(game)
    n = len(game.hand)
    for i in range(n):
        if view.surely_playable(i):
            return ("play", i)
    for i in range(n):
        if view.surely_useless(i):
            return ("discard", i)
    if game.hints > 0 and game.useful_hints():
        return ("hint", -1)
    for i in range(n):
        if not view.maybe_valuable(i):
            return ("discard", i)
    return ("discard", 0)


def joker_target(game: Game, index: int) -> int | None:
    if not game.needs_target(index):
        return None
    card = game.hand[index]
    for c in PILES:
        if game.fireworks.fits(card, c):
            return c
    return RED


def apply_move(game: Game, move: Move) -> None:
    kind, index = move
    if kind == "play":
        game.play(index, joker_target(game, index))
    else:
        game.discard(index)
