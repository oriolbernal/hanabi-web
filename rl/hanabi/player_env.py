"""Gymnasium environment where the agent is the player.

Each step is one turn: play a card, discard a card or ask for a hint, which
the (fixed) hint policy answers. The agent only sees what a person would:
hint information, probabilities derived from it, and the public table.

Reward: points scored, plus optional potential-based shaping with the
reachable score, F = shaping * (gamma * Phi(s') - Phi(s)) with Phi = max
score and Phi = 0 once the game is over, so a discard that throws away the
last copy of a needed card is felt right away. Phi must be 0 at the end:
otherwise ending the game early (losing all lives) dodges the penalties of
later discards and the agent learns to do exactly that.
"""

from __future__ import annotations

import random

import gymnasium as gym
import numpy as np

from .game import (
    ALLOWED_ERRORS,
    COLORS,
    HAND_SIZE,
    MAX_HINTS,
    PILES,
    Game,
    PlayerView,
    build_deck,
    copies,
    joker_target,
)
from .hint_policy import HintPolicy

SLOT_FEATURES = 28
PLAYER_OBSERVATION_SIZE = HAND_SIZE * SLOT_FEATURES + 5 + 30 + 3 + 1
PLAYER_ACTIONS = 2 * HAND_SIZE + 1  # play 0-4, discard 5-9, hint 10
HINT_ACTION = 2 * HAND_SIZE


def encode_player(game: Game) -> np.ndarray:
    """Only public information and what hints revealed. Must match Dart."""
    obs: list[float] = []
    view = PlayerView(game)
    for i in range(HAND_SIZE):
        if i >= len(game.hand):
            obs += [0.0] * SLOT_FEATURES
            continue
        card = game.hand[i]
        obs += [1, card.known_number, card.known_color]
        obs += [1 if card.known_number and card.number == n else 0 for n in range(1, 6)]
        obs += [1 if card.known_color and card.color == c else 0 for c in range(COLORS)]
        obs += [1 if n in card.not_numbers else 0 for n in range(1, 6)]
        obs += [1 if c in card.not_colors else 0 for c in range(COLORS)]
        obs += [
            view.play_probability(i),
            view.useless_probability(i),
            view.expected_discard_loss(i) / 5,
        ]
    obs += [game.fireworks.top_number(c) / 5 for c in PILES]
    for c in range(COLORS):
        for n in range(1, 6):
            gone = sum(1 for d in game.discarded if d.number == n and d.color == c)
            obs.append(gone / copies(n, c))
    obs += [game.hints / MAX_HINTS, game.errors / ALLOWED_ERRORS, len(game.deck) / 50]
    obs.append(game.max_score() / 25)
    return np.asarray(obs, dtype=np.float32)


def player_mask(game: Game) -> np.ndarray:
    mask = np.zeros(PLAYER_ACTIONS, dtype=bool)
    n = len(game.hand)
    mask[:n] = True
    mask[HAND_SIZE : HAND_SIZE + n] = True
    mask[HINT_ACTION] = game.hints > 0 and bool(game.useful_hints())
    return mask


def apply_player_action(game: Game, action: int, hint_policy: HintPolicy) -> None:
    if action == HINT_ACTION:
        game.hints -= 1
        game.apply_hint(hint_policy(game))
    elif action < HAND_SIZE:
        game.play(action, joker_target(game, action))
    else:
        game.discard(action - HAND_SIZE)


class PlayerEnv(gym.Env):
    metadata = {"render_modes": []}

    def __init__(self, hint_policy: str, shaping: float = 0.0, gamma: float = 0.99) -> None:
        self.hint_policy = HintPolicy(hint_policy)
        self.shaping = shaping
        self.gamma = gamma
        self.observation_space = gym.spaces.Box(0.0, 1.0, (PLAYER_OBSERVATION_SIZE,), np.float32)
        self.action_space = gym.spaces.Discrete(PLAYER_ACTIONS)
        self.game: Game | None = None
        self._rng = random.Random()

    def reset(self, *, seed: int | None = None, options=None):
        super().reset(seed=seed)
        if seed is not None:
            self._rng.seed(seed)
        self.game = Game(build_deck(self._rng))
        return encode_player(self.game), {}

    def step(self, action: int):
        game = self.game
        assert player_mask(game)[action], "action mask violated"
        score, reach = game.score, game.max_score()
        apply_player_action(game, int(action), self.hint_policy)
        reward = float(game.score - score)
        done = game.is_over
        if self.shaping:
            potential = 0.0 if done else game.max_score()
            reward += self.shaping * (self.gamma * potential - reach)
        obs = np.zeros(PLAYER_OBSERVATION_SIZE, np.float32) if done else encode_player(game)
        return obs, reward, done, False, {"score": game.score} if done else {}

    def action_masks(self) -> np.ndarray:
        if self.game is None or self.game.is_over:
            return np.ones(PLAYER_ACTIONS, dtype=bool)
        return player_mask(self.game)
