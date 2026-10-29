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
            chance = {a: play_chance_after(game, a) for a in allowed}
            best = max(chance.values())
            if best >= 0.5 and best > play_chance_after(game, None) + 1e-9:
                allowed = [a for a in allowed if chance[a] >= best - 1e-9]
        scores = self.logits(self.encode(game))
        best = allowed[0]
        for a in allowed[1:]:
            if scores[a] > scores[best]:
                best = a
        return action_to_hint(best)


def play_chance_after(game: Game, action: int | None) -> float:
    """Port of RlStrategy.playChanceAfter: best chance, for the player, of
    playing a card that really fits after the hint (or none)."""
    g = game
    if action is not None:
        g = game.copy()
        g.apply_hint(action_to_hint(action))
    fits = game.fireworks.playable_cards()
    view = PlayerView(g)
    best = 0.0
    for i, card in enumerate(g.hand):
        if any(card.same_as(f) for f in fits):
            best = max(best, view.play_probability(i))
    return best


assert ACTION_COUNT == 11
