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


# Feature set v2 appends, for each action, what giving that hint would do.
ACTION_FEATURES = 5
OBSERVATION_SIZE_V2 = OBSERVATION_SIZE + ACTION_COUNT * ACTION_FEATURES


def sure_counts(game: Game) -> tuple[int, int]:
    view = PlayerView(game)
    playable = sum(view.surely_playable(i) for i in range(len(game.hand)))
    useless = sum(view.surely_useless(i) for i in range(len(game.hand)))
    return playable, useless


def encode_action_effects(game: Game) -> list[float]:
    """Per action: change in surely playable cards, change in surely useless
    cards, cards touched, touched cards really playable, touched critical."""
    playable0, useless0 = sure_counts(game)
    really_playable = game.fireworks.playable_cards()
    useful = {hint_to_action(h) for h in game.useful_hints()}
    out: list[float] = []
    for a in range(ACTION_COUNT):
        if a not in useful:
            out += [0.0] * ACTION_FEATURES
            continue
        kind, value = action_to_hint(a)
        touched = [
            c for c in game.hand if (c.number if kind == "n" else c.color) == value
        ]
        saved = game.hand
        game.hand = [c.copy() for c in saved]
        game.apply_hint((kind, value))
        playable, useless = sure_counts(game)
        game.hand = saved
        out += [
            (playable - playable0) / 5,
            (useless - useless0) / 5,
            len(touched) / 5,
            sum(any(c.same_as(p) for p in really_playable) for c in touched) / 5,
            sum(is_critical(game, c) for c in touched) / 5,
        ]
    return out


def encode_v2(game: Game) -> np.ndarray:
    return np.concatenate([encode(game), np.asarray(encode_action_effects(game), np.float32)])


OBSERVATION_SIZE_V3 = OBSERVATION_SIZE_V2 + HAND_SIZE + 1


def encode_v3(game: Game) -> np.ndarray:
    """v2 plus discard loss of each card and the reachable score."""
    extra = [game.discard_loss(game.hand[i]) / 5 if i < len(game.hand) else 0.0 for i in range(HAND_SIZE)]
    extra.append(game.max_score() / 25)
    return np.concatenate([encode_v2(game), np.asarray(extra, np.float32)])


NEXT_MOVE_FEATURES = 7
OBSERVATION_SIZE_V4 = OBSERVATION_SIZE_V3 + ACTION_COUNT * NEXT_MOVE_FEATURES


def encode_next_moves(game: Game) -> list[float]:
    """Per hint (zeros when useless): the move the expert player makes right
    after it (play, discard, hint asked), whether the played card fits,
    whether the discard costs nothing, the points it costs (of 5), and the
    best chance, from the player's view, of a card that really fits."""
    from .game import PLAYERS

    expert = PLAYERS["expert"]
    useful = {hint_to_action(h) for h in game.useful_hints()}
    fits = game.fireworks.playable_cards()
    out: list[float] = []
    for a in range(ACTION_COUNT):
        if a not in useful:
            out += [0.0] * NEXT_MOVE_FEATURES
            continue
        g = game.copy()
        g.hints -= 1
        g.apply_hint(action_to_hint(a))
        kind, index = expert(g)
        view = PlayerView(g)
        chance = 0.0
        for i, card in enumerate(g.hand):
            if any(card.same_as(p) for p in fits):
                chance = max(chance, view.play_probability(i))
        if kind == "play":
            out += [1, 0, 0, float(any(g.hand[index].same_as(p) for p in fits)), 0, 0, chance]
        elif kind == "discard":
            loss = g.discard_loss(g.hand[index])
            out += [0, 1, 0, 0, float(loss == 0), loss / 5, chance]
        else:
            out += [0, 0, 1, 0, 0, 0, chance]
    return out


def encode_v4(game: Game) -> np.ndarray:
    return np.concatenate([encode_v3(game), np.asarray(encode_next_moves(game), np.float32)])


ENCODERS = {
    "v1": (encode, OBSERVATION_SIZE),
    "v2": (encode_v2, OBSERVATION_SIZE_V2),
    "v3": (encode_v3, OBSERVATION_SIZE_V3),
    "v4": (encode_v4, OBSERVATION_SIZE_V4),
}
