"""Replays games exported by `dart run bin/export_parity.dart` and checks the
Python port makes the same decisions, sees the same observations and ends
with the same score."""

import json
from pathlib import Path

import numpy as np
import pytest

from hanabi.encoding import encode, hint_to_action
from hanabi.game import Card, Game, apply_move, careful_move, dummy_hint

FIXTURE = Path(__file__).parent.parent / "fixtures" / "parity.json"


@pytest.fixture(scope="module")
def games():
    if not FIXTURE.exists():
        pytest.skip("run `dart run bin/export_parity.dart` first")
    return json.loads(FIXTURE.read_text())


def replay(deck):
    game = Game([Card(n, c) for n, c in deck])
    steps, turns = [], 0
    while not game.is_over:
        turns += 1
        move = careful_move(game)
        if move[0] == "hint":
            hint = dummy_hint(game)
            if hint is None:
                game.discard(0)
                continue
            steps.append((encode(game), hint_to_action(hint)))
            game.hints -= 1
            game.apply_hint(hint)
        else:
            apply_move(game, move)
    return game.score, turns, steps


def test_same_games_as_dart(games):
    for seed, expected in enumerate(games):
        score, turns, steps = replay(expected["deck"])
        assert len(steps) == len(expected["steps"]), f"seed {seed}"
        for k, ((obs, action), ref) in enumerate(zip(steps, expected["steps"])):
            assert action == ref["action"], f"seed {seed} step {k}"
            np.testing.assert_allclose(obs, ref["obs"], atol=1e-6, err_msg=f"seed {seed} step {k}")
        assert (score, turns) == (expected["score"], expected["turns"]), f"seed {seed}"


def test_observation_size_matches_space():
    from hanabi.encoding import OBSERVATION_SIZE
    from hanabi.env import HintEnv

    obs, _ = HintEnv().reset(seed=0)
    assert obs.shape == (OBSERVATION_SIZE,)
