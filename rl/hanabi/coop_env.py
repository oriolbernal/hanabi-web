"""Self-play environment for the co-op game: every seat is the same agent.

One step is one turn, taken by whoever's turn it is; the observation is
what that player sees, seats counted from them (they are seat 0, the next
player 1, ...). The reward is the team's: points added to the fireworks by
the move. Nothing in here tells the agent what a good move is; it only
gets the rules (which moves are legal) and the score.

Observation (OBS_SIZE numbers), raw facts only:
- each other player's cards: identity (30 = 5 numbers x 6 colors) and what
  that player knows about it (5 + 6 possible numbers and colors);
- own cards: what this player knows (5 + 6) and whether the slot is used;
- unseen cards: how many of each identity are neither played, discarded
  nor in sight, out of how many there were;
- fireworks (top number per pile), the floating joker pile, hint tokens,
  lives, deck size, number of players;
- the last hint each player received since their own turn (cards touched
  and its focus), and the last move of each other player.

Rewards (Rewards): points added to the fireworks, plus the shaping below,
whose weights are set per run:
- a play that misfires: -misfire;
- a discard of a card that can never be played again: +useless;
- a discard that lowers the best score still reachable (the last copy of a
  card a pile needs): -lost_point for each point lost;
- a discard of a card still needed but with copies left: -needed / copies
  left (the fewer remain, the more it costs);
- reaching 25: +perfect.
The evaluation always reports the plain score.

Actions (N_ACTIONS): play slot i (5), play joker in slot i on pile c (25),
discard slot i (5), hint the player k seats ahead about a number (3 x 5)
or a color (3 x 6).
"""

from __future__ import annotations

import random
from dataclasses import dataclass

import numpy as np

from .coop import MAX_PLAYERS, CoopGame
from .game import ALLOWED_ERRORS, COLORS, HAND_SIZE, MAX_HINTS, PILES, Card, Game, build_deck, copies

N_ID = 5 * COLORS  # card identities: (number - 1) * 6 + color

PLAY, PLAY_ON, DISCARD, HINT_N, HINT_C = 0, 5, 30, 35, 50
N_ACTIONS = 68


def ident(c: Card) -> int:
    return (c.number - 1) * COLORS + c.color


def _possible(card: Card) -> tuple[list[int], list[int]]:
    numbers = [card.number] if card.known_number else [n for n in range(1, 6) if n not in card.not_numbers]
    colors = [card.color] if card.known_color else [c for c in range(COLORS) if c not in card.not_colors]
    return numbers, colors


def _dead(g: CoopGame, card: Card) -> bool:
    """Whether [card] can never be played: its pile (every pile, for a joker) is past it."""
    piles = PILES if card.is_joker else (card.color,)
    return all(g.fireworks.top_number(p) >= card.number for p in piles)


# Layout.
_OTHER = N_ID + 11  # per card in another hand
_OWN = 12  # per own card
_OFF_OTHERS = 0
_OFF_OWN = _OFF_OTHERS + (MAX_PLAYERS - 1) * HAND_SIZE * _OTHER
_OFF_UNSEEN = _OFF_OWN + HAND_SIZE * _OWN
_OFF_TABLE = _OFF_UNSEEN + N_ID
_TABLE = 5 * 6 + 6 + 11 + 4 + 1 + 3
_OFF_RECEIVED = _OFF_TABLE + _TABLE
_RECEIVED = HAND_SIZE * 2 + 1
_OFF_LAST = _OFF_RECEIVED + MAX_PLAYERS * _RECEIVED
# kind (play, discard, hint), slot, hint receiver (seats from me), hinted
# number, hinted color, whether a play fitted.
_LAST = 3 + 5 + 4 + 5 + 6 + 1
_L_SLOT, _L_TO, _L_N, _L_C, _L_FITS = 3, 8, 12, 17, 23
OBS_SIZE = _OFF_LAST + (MAX_PLAYERS - 1) * _LAST

_TOTAL = np.array([copies(n, c) for n in range(1, 6) for c in range(COLORS)], dtype=np.float32)


@dataclass
class Rewards:
    misfire: float = 1.0
    useless: float = 0.1
    lost_point: float = 1.0
    needed: float = 0.2
    perfect: float = 5.0


def max_score(game: CoopGame) -> int:
    """Best score still reachable (the solitaire's rule fits: discards and piles)."""
    return Game.max_score(game)  # type: ignore[arg-type]


class CoopEnv:
    def __init__(self, players: int, seed: int | None = None, rewards: Rewards | None = None) -> None:
        self.players = players
        self.rewards = rewards or Rewards()
        self.rng = random.Random(seed)
        self.reset()

    def reset(self) -> None:
        self.game = CoopGame(self.players, build_deck(self.rng))
        # Last move of each player: (kind, slot, to, hint, fits).
        self.last: list[tuple | None] = [None] * self.players

    # --- actions -----------------------------------------------------------

    def legal_mask(self) -> np.ndarray:
        g = self.game
        mask = np.zeros(N_ACTIONS, dtype=bool)
        hand = g.hands[g.current]
        for i, c in enumerate(hand):
            mask[DISCARD + i] = True
            if c.is_joker and c.number != 1:
                for p in PILES:
                    mask[PLAY_ON + i * 5 + p] = True
            else:
                mask[PLAY + i] = True
        if g.hints > 0:
            for k in range(1, g.players):
                to = (g.current + k) % g.players
                for c in g.hands[to]:
                    mask[HINT_N + (k - 1) * 5 + c.number - 1] = True
                    mask[HINT_C + (k - 1) * 6 + c.color] = True
        return mask

    def decode(self, action: int):
        g = self.game
        if action < PLAY_ON:
            return ("p", action, None)
        if action < DISCARD:
            i, p = divmod(action - PLAY_ON, 5)
            return ("p", i, p)
        if action < HINT_N:
            return ("d", action - DISCARD)
        if action < HINT_C:
            k, n = divmod(action - HINT_N, 5)
            return ("h", (g.current + k + 1) % g.players, ("n", n + 1))
        k, c = divmod(action - HINT_C, 6)
        return ("h", (g.current + k + 1) % g.players, ("c", c))

    def step(self, action: int) -> tuple[float, bool]:
        """Plays [action] for the current player; returns (reward, over)."""
        g = self.game
        w = self.rewards
        move = self.decode(action)
        me = g.current
        before = g.score
        reward = 0.0
        if move[0] == "p":
            card = g.hands[me][move[1]]
            lives = g.errors
            fits = g.play(move[1], move[2])
            if g.errors < lives:
                reward -= w.misfire
            self.last[me] = ("p", move[1], None, ident(card), fits)
        elif move[0] == "d":
            card = g.hands[me][move[1]]
            reachable = max_score(g)
            dead = _dead(g, card)
            g.discard(move[1])
            lost = reachable - max_score(g)
            if lost > 0:
                reward -= w.lost_point * lost
            elif dead:
                reward += w.useless
            else:
                left = copies(card.number, card.color) - sum(
                    1 for c in g.discarded if c.number == card.number and c.color == card.color
                )
                reward -= w.needed / max(left, 1)
            self.last[me] = ("d", move[1], None, ident(card), True)
        else:
            g.hint(move[1], move[2])
            self.last[me] = ("h", None, move[1], move[2], True)
        reward += g.score - before
        if g.is_over and g.score == 25:
            reward += w.perfect
        return reward, g.is_over

    # --- observation -------------------------------------------------------

    def observe(self) -> np.ndarray:
        g = self.game
        me = g.current
        o = np.zeros(OBS_SIZE, dtype=np.float32)
        unseen = _TOTAL.copy()
        for c in g.discarded:
            unseen[ident(c)] -= 1
        for p in PILES:
            for c in g.fireworks.piles[p]:
                unseen[ident(c)] -= 1
        # Others' cards.
        for k in range(1, g.players):
            hand = g.hands[(me + k) % g.players]
            for i, c in enumerate(hand):
                base = _OFF_OTHERS + ((k - 1) * HAND_SIZE + i) * _OTHER
                o[base + ident(c)] = 1
                unseen[ident(c)] -= 1
                numbers, colors = _possible(c)
                for n in numbers:
                    o[base + N_ID + n - 1] = 1
                for col in colors:
                    o[base + N_ID + 5 + col] = 1
        # Own cards: knowledge only.
        for i, c in enumerate(g.hands[me]):
            base = _OFF_OWN + i * _OWN
            numbers, colors = _possible(c)
            for n in numbers:
                o[base + n - 1] = 1
            for col in colors:
                o[base + 5 + col] = 1
            o[base + 11] = 1
        o[_OFF_UNSEEN : _OFF_UNSEEN + N_ID] = unseen / _TOTAL
        # Table.
        t = _OFF_TABLE
        for p in PILES:
            o[t + p * 6 + g.fireworks.top_number(p)] = 1
        floating = g.fireworks.floating_joker()
        o[t + 30 + (5 if floating is None else floating)] = 1
        o[t + 36 + g.hints] = 1
        o[t + 47 + g.errors] = 1
        o[t + 51] = g.deck_size / 50
        o[t + 52 + g.players - 2] = 1
        # Hints received, seats counted from me.
        for k in range(g.players):
            r = g.received[(me + k) % g.players]
            if r is None:
                continue
            base = _OFF_RECEIVED + k * _RECEIVED
            for i in r.touched:
                o[base + i] = 1
            o[base + HAND_SIZE + r.focus] = 1
            o[base + 2 * HAND_SIZE] = 1
        # Last move of each other player.
        for k in range(1, g.players):
            last = self.last[(me + k) % g.players]
            if last is None:
                continue
            base = _OFF_LAST + (k - 1) * _LAST
            kind, slot, to, what, fits = last
            o[base + "pdh".index(kind)] = 1
            if kind == "h":
                o[base + _L_TO + (to - me) % g.players] = 1
                hk, value = what
                if hk == "n":
                    o[base + _L_N + value - 1] = 1
                else:
                    o[base + _L_C + value] = 1
            else:
                o[base + _L_SLOT + slot] = 1
                o[base + _L_FITS] = 1 if fits else 0
        return o


assert N_ACTIONS == HINT_C + 3 * 6
assert _TABLE == 5 * 6 + 6 + (MAX_HINTS + 1) + (ALLOWED_ERRORS + 1) + 1 + 3
