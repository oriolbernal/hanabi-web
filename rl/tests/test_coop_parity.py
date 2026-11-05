"""Replays random co-op games exported by `dart run bin/export_coop_parity.dart`
and checks the Python port reaches exactly the same state after every move."""

import json
from pathlib import Path

import pytest

from hanabi.coop import CoopGame, digest, parse_deck, parse_move

FIXTURE = Path(__file__).parent.parent / "fixtures" / "coop_parity.json"


@pytest.fixture(scope="module")
def games():
    if not FIXTURE.exists():
        pytest.skip("run `dart run bin/export_coop_parity.dart` first")
    return json.loads(FIXTURE.read_text())


def test_every_state_matches(games):
    for g in games:
        game = CoopGame(g["players"], parse_deck(g["deck"]))
        assert digest(game) == g["states"][0]
        for i, text in enumerate(g["moves"]):
            move = parse_move(text)
            assert game.is_legal(move), (text, i)
            game.apply(move)
            assert digest(game) == g["states"][i + 1], (g["deck"], i, text)
        assert game.is_over
