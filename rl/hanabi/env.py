"""Gymnasium environment where the agent is the hint giver.

Each step is one hint. Between hints the simulated player keeps playing and
discarding until it asks for the next hint or the game ends. With
players="mixed" every episode uses a random profile from PLAYERS, so the
policy learns to help careful and bold players alike.
The reward is the points scored in between, minus `hint_cost` per hint, so
an episode's total reward is the final score minus the cost of the hints.
"""

from __future__ import annotations

import random

import gymnasium as gym
import numpy as np

from .encoding import ACTION_COUNT, ENCODERS, action_mask, action_to_hint
from .game import PLAYERS, Game, apply_move, build_deck


class HintEnv(gym.Env):
    metadata = {"render_modes": []}

    def __init__(
        self, features: str = "v1", hint_cost: float = 0.0, players: str = "careful"
    ) -> None:
        self.encode, self.size = ENCODERS[features]
        self.hint_cost = hint_cost
        # "mixed": every rule-based profile; "agent:<json>[:<share>]" adds the
        # trained player agent, used in <share> of the games (default 0.5).
        self.agent = None
        self.agent_share = 0.0
        if players.startswith("agent:"):
            from .player_env import PlayerAgent

            path, _, share = players[len("agent:") :].partition(":")
            self.agent = PlayerAgent(path)
            self.agent_share = float(share or 0.5)
            players = "mixed"
        self.players = list(PLAYERS) if players == "mixed" else [players]
        self.player = PLAYERS[self.players[0]]
        low = 0.0 if features == "v1" else -1.0  # v2 effects are deltas
        self.observation_space = gym.spaces.Box(low, 1.0, (self.size,), np.float32)
        self.action_space = gym.spaces.Discrete(ACTION_COUNT)
        self.game: Game | None = None
        self._rng = random.Random()

    def reset(self, *, seed: int | None = None, options=None):
        super().reset(seed=seed)
        if seed is not None:
            self._rng.seed(seed)
        self.game = Game(build_deck(self._rng))
        if self.agent is not None and self._rng.random() < self.agent_share:
            self.player = self.agent
        else:
            self.player = PLAYERS[self._rng.choice(self.players)]
        self._advance()
        # A game always starts with the player asking for a hint.
        assert not self.game.is_over
        return self.encode(self.game), {}

    def step(self, action: int):
        game = self.game
        hint = action_to_hint(int(action))
        assert hint in game.useful_hints(), "action mask violated"
        before = game.score
        game.hints -= 1
        game.apply_hint(hint)
        self._advance()
        reward = float(game.score - before) - self.hint_cost
        done = game.is_over
        obs = np.zeros(self.size, np.float32) if done else self.encode(game)
        return obs, reward, done, False, {"score": game.score} if done else {}

    def action_masks(self) -> np.ndarray:
        """Used by MaskablePPO: only hints that reveal something are allowed."""
        if self.game is None or self.game.is_over:
            return np.ones(ACTION_COUNT, dtype=bool)
        return action_mask(self.game)

    def _advance(self) -> None:
        """Let the player act until it wants a hint or the game ends."""
        game = self.game
        while not game.is_over:
            move = self.player(game)
            if move[0] == "hint":
                return
            apply_move(game, move)
