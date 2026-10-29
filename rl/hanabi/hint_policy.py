"""Run an exported hint policy (the JSON used by the app) with numpy, so the
player agent can train against the same hint giver the app uses."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from .encoding import ACTION_COUNT, ENCODERS, action_to_hint, hint_to_action
from .game import Game, PlayerView


class HintPolicy:
    def __init__(self, path: str | Path, play_first: bool = True) -> None:
        data = json.loads(Path(path).read_text())
        self.encode = ENCODERS[data.get("features", "v1")][0]
        self.layers = [(np.asarray(l["w"]), np.asarray(l["b"])) for l in data["layers"]]
        self.play_first = play_first

    def logits(self, obs: np.ndarray) -> np.ndarray:
        x = obs.astype(np.float64)
        for i, (w, b) in enumerate(self.layers):
            x = w @ x + b
            if i < len(self.layers) - 1:
                x = np.tanh(x)
        return x

    def __call__(self, game: Game):
        allowed = [hint_to_action(h) for h in game.useful_hints()]
        if not allowed:
            return None
        if self.play_first:
            playable = [a for a in allowed if _unlocks_play(game, a)]
            if playable:
                allowed = playable
        scores = self.logits(self.encode(game))
        best = allowed[0]
        for a in allowed[1:]:
            if scores[a] > scores[best]:
                best = a
        return action_to_hint(best)


def _surely_playable_count(game: Game) -> int:
    view = PlayerView(game)
    return sum(view.surely_playable(i) for i in range(len(game.hand)))


def _unlocks_play(game: Game, action: int) -> bool:
    before = _surely_playable_count(game)
    sim = game.copy()
    sim.apply_hint(action_to_hint(action))
    return _surely_playable_count(sim) > before


assert ACTION_COUNT == 11
