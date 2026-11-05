"""Python port of lib/game/coop.dart: the cooperative game for 2-4 players.

It must behave exactly like the Dart code: tests/test_coop_parity.py replays
random games exported by `dart run bin/export_coop_parity.dart` and checks
the whole state after every move.

Moves are tuples: ("p", index, target or None), ("d", index),
("h", to, ("n", number) or ("c", color)).
"""

from __future__ import annotations

from dataclasses import dataclass

from .game import ALLOWED_ERRORS, HAND_SIZE, JOKER, MAX_HINTS, PILES, Card, Fireworks

MAX_PLAYERS = 4


@dataclass
class ReceivedHint:
    """The last hint a player received since their own last turn."""

    giver: int
    hint: tuple[str, int]
    touched: list[int]
    chop: int

    @property
    def focus(self) -> int:
        return self.chop if self.chop in self.touched else max(self.touched)


def touches(card: Card, hint: tuple[str, int]) -> bool:
    kind, value = hint
    return card.number == value if kind == "n" else card.color == value


class CoopGame:
    def __init__(self, players: int, deck: list[Card]) -> None:
        assert 2 <= players <= MAX_PLAYERS
        self.players = players
        self.deck = deck
        self.fireworks = Fireworks()
        self.hands: list[list[Card]] = []
        self.discarded: list[Card] = []
        self.received: list[ReceivedHint | None] = []
        self.hints = MAX_HINTS
        self.errors = ALLOWED_ERRORS
        self.current = 0
        for p in range(players):
            self.received.append(None)
            self.hands.append([])
            for _ in range(HAND_SIZE):
                self._draw(p)

    @property
    def deck_size(self) -> int:
        return len(self.deck)

    @property
    def score(self) -> int:
        return self.fireworks.score

    @property
    def is_over(self) -> bool:
        return self.fireworks.victory or self.errors == 0 or all(not h for h in self.hands)

    def needs_target(self, index: int) -> bool:
        card = self.hands[self.current][index]
        return card.is_joker and card.number != 1

    def hints_for(self, player: int) -> list[tuple[str, int]]:
        """Hints that reveal something new to [player], in the Dart order."""
        result: list[tuple[str, int]] = []
        for card in self.hands[player]:
            if not card.known_number and ("n", card.number) not in result:
                result.append(("n", card.number))
            if not card.known_color and ("c", card.color) not in result:
                result.append(("c", card.color))
        return result

    def play(self, index: int, target: int | None = None) -> bool:
        hand = self.hands[self.current]
        card = hand.pop(index)
        card.reveal()
        self._draw(self.current)
        fits = self.fireworks.play(card, target)
        if not fits:
            self.discarded.append(card)
            self.errors -= 1
        self._end_turn()
        return fits

    def discard(self, index: int) -> Card:
        card = self.hands[self.current].pop(index)
        card.reveal()
        self.discarded.append(card)
        self._draw(self.current)
        if self.hints < MAX_HINTS:
            self.hints += 1
        self._end_turn()
        return card

    def hint(self, to: int, hint: tuple[str, int]) -> list[Card]:
        assert to != self.current and self.hints > 0
        self.hints -= 1
        hand = self.hands[to]
        chop = next((i for i, c in enumerate(hand) if not c.known_number and not c.known_color), -1)
        kind, value = hint
        touched = []
        for card in hand:
            if touches(card, hint):
                if kind == "n":
                    card.known_number = True
                else:
                    card.known_color = True
                touched.append(card)
            elif kind == "n":
                card.rule_out_number(value)
            else:
                card.rule_out_color(value)
        self.received[to] = ReceivedHint(
            self.current,
            hint,
            [i for i, c in enumerate(hand) if any(c is t for t in touched)],
            chop,
        )
        self._end_turn()
        return touched

    def is_legal(self, move) -> bool:
        if self.is_over:
            return False
        hand = self.hands[self.current]
        if move[0] == "p":
            _, index, target = move
            return 0 <= index < len(hand) and self.needs_target(index) == (target is not None)
        if move[0] == "d":
            return 0 <= move[1] < len(hand)
        _, to, hint = move
        if to == self.current or not 0 <= to < self.players or self.hints == 0:
            return False
        return any(touches(c, hint) for c in self.hands[to])

    def apply(self, move) -> None:
        if move[0] == "p":
            self.play(move[1], move[2])
        elif move[0] == "d":
            self.discard(move[1])
        else:
            self.hint(move[1], move[2])

    def _draw(self, player: int) -> None:
        if self.deck:
            self.hands[player].append(self.deck.pop(0))

    def _end_turn(self) -> None:
        if self.hands:
            self.received[self.current] = None
        if self.is_over:
            return
        while True:
            self.current = (self.current + 1) % self.players
            if self.hands[self.current]:
                break


SYMBOLS = "RGBYW*"


def parse_move(text: str):
    """A move in the app's text form (p3, p3B, d0, h2:5, h1:R)."""
    if text[0] == "p":
        return ("p", int(text[1]), SYMBOLS.index(text[2]) if len(text) > 2 else None)
    if text[0] == "d":
        return ("d", int(text[1]))
    to, what = text[1:].split(":")
    return ("h", int(to), ("n", int(what)) if what.isdigit() else ("c", SYMBOLS.index(what)))


def parse_deck(text: str) -> list[Card]:
    return [Card(int(text[i]), SYMBOLS.index(text[i + 1])) for i in range(0, len(text), 2)]


def digest(game: CoopGame) -> str:
    """The whole state as text, the same as bin/export_coop_parity.dart."""

    def card(c: Card) -> str:
        return (
            f"{c.number}{SYMBOLS[c.color]}"
            f"{'n' if c.known_number else '-'}{'c' if c.known_color else '-'}"
            f"{''.join(str(n) for n in sorted(c.not_numbers))}/"
            f"{''.join(SYMBOLS[x] for x in sorted(c.not_colors))}"
        )

    def received(r: ReceivedHint | None) -> str:
        if r is None:
            return "-"
        kind, value = r.hint
        what = str(value) if kind == "n" else SYMBOLS[value]
        return f"{r.giver}:{what}:{','.join(map(str, r.touched))}:{r.chop}:{r.focus}"

    piles = "".join(str(game.fireworks.top_number(c)) for c in PILES)
    floating = game.fireworks.floating_joker()
    return "|".join(
        [
            " ".join(card(c) for c in hand)
            for hand in game.hands
        ]
        + [
            piles,
            "-" if floating is None else str(floating),
            str(game.hints),
            str(game.errors),
            str(game.current),
            str(game.deck_size),
            "".join(f"{c.number}{SYMBOLS[c.color]}" for c in game.discarded),
            " ".join(received(r) for r in game.received),
            "over" if game.is_over else "on",
            str(game.score),
        ]
    )


__all__ = ["CoopGame", "ReceivedHint", "parse_move", "parse_deck", "digest", "JOKER"]
