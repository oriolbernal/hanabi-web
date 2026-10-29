"""Replays games from `dart run bin/export_player_parity.dart`: the player
observation must match Dart's, and the exported agent run in Dart must pick
the same action as the PyTorch model."""

import json
from pathlib import Path

import numpy as np
import pytest

from hanabi.game import PLAYERS, Card, Game, apply_move, dummy_hint
from hanabi.player_env import HAND_SIZE, HINT_ACTION, encode_player, player_mask

FIXTURE = Path(__file__).parent.parent / "fixtures" / "player_parity.json"
MODEL = Path(__file__).parent.parent / "models" / "P4.zip"


@pytest.fixture(scope="module")
def games():
    if not FIXTURE.exists():
        pytest.skip("run `dart run bin/export_player_parity.dart` first")
    return json.loads(FIXTURE.read_text())


def test_player_observation_matches_dart(games):
    model = None
    if MODEL.exists():
        from sb3_contrib import MaskablePPO

        model = MaskablePPO.load(MODEL, device="cpu")
    bold = PLAYERS["bold"]
    for seed, expected in enumerate(games):
        game = Game([Card(n, c) for n, c in expected["deck"]])
        for k, ref in enumerate(expected["turns"]):
            obs = encode_player(game)
            np.testing.assert_allclose(obs, ref["obs"], atol=1e-6, err_msg=f"seed {seed} turn {k}")
            if model is not None:
                action, _ = model.predict(obs, action_masks=player_mask(game), deterministic=True)
                assert int(action) == ref["agent"], f"seed {seed} turn {k}"
            move = bold(game)
            kind, index = move
            action = {"play": index, "discard": HAND_SIZE + index, "hint": HINT_ACTION}[kind]
            assert action == ref["action"], f"seed {seed} turn {k}"
            if kind == "hint":
                game.hints -= 1
                game.apply_hint(dummy_hint(game))
            else:
                apply_move(game, move)
        assert game.is_over and game.score == expected["score"], f"seed {seed}"
