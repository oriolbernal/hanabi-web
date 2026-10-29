"""Observation and action encoding. Must match lib/sim/rl_strategy.dart."""

from __future__ import annotations

import numpy as np

from .game import (
    ALLOWED_ERRORS,
    COLORS,
    HAND_SIZE,
    MAX_HINTS,
    PILES,
    Game,
    Hint,
    PlayerView,
    copies,
    is_critical,
    is_dead,
)

SLOT_FEATURES = 19
OBSERVATION_SIZE = HAND_SIZE * SLOT_FEATURES + 5 + 30 + 3
ACTION_COUNT = 11  # 0-4: numbers 1-5, 5-10: colors


def action_to_hint(action: int) -> Hint:
    return ("n", action + 1) if action < 5 else ("c", action - 5)


def hint_to_action(hint: Hint) -> int:
    kind, value = hint
    return value - 1 if kind == "n" else 5 + value


def action_mask(game: Game) -> np.ndarray:
    mask = np.zeros(ACTION_COUNT, dtype=bool)
    for hint in game.useful_hints():
        mask[hint_to_action(hint)] = True
    return mask


def encode(game: Game) -> np.ndarray:
    obs: list[float] = []
    view = PlayerView(game)
    playable = game.fireworks.playable_cards()

    for i in range(HAND_SIZE):
        if i >= len(game.hand):
            obs += [0.0] * SLOT_FEATURES
            continue
        card = game.hand[i]
        obs.append(1)
        obs += [1 if card.number == n else 0 for n in range(1, 6)]
        obs += [1 if card.color == c else 0 for c in range(COLORS)]
        obs += [
            card.known_number,
            card.known_color,
            any(card.same_as(p) for p in playable),
            is_critical(game, card),
            is_dead(game, card),
            view.surely_playable(i),
            view.surely_useless(i),
        ]

    obs += [game.fireworks.top_number(c) / 5 for c in PILES]

    for c in range(COLORS):
        for n in range(1, 6):
            gone = sum(1 for d in game.discarded if d.number == n and d.color == c)
            obs.append(gone / copies(n, c))

    obs += [game.hints / MAX_HINTS, game.errors / ALLOWED_ERRORS, len(game.deck) / 50]
    return np.asarray(obs, dtype=np.float32)
