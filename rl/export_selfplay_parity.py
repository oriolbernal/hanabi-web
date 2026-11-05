"""Writes what the self-play bot sees at every turn of the reference games
(fixtures/coop_parity.json), for test/selfplay_test.dart to check that the
Dart encoding (lib/sim/selfplay_bot.dart) matches rl/hanabi/coop_env.py.

    uv run python export_selfplay_parity.py
"""

import json
from pathlib import Path

import numpy as np

from hanabi.coop import CoopGame, parse_deck, parse_move
from hanabi.coop_env import CoopEnv, DISCARD, HINT_C, HINT_N, PLAY, PLAY_ON

ROOT = Path(__file__).parent


def encode(env: CoopEnv, move) -> int:
    g = env.game
    if move[0] == "p":
        _, i, target = move
        return PLAY_ON + i * 5 + target if g.needs_target(i) else PLAY + i
    if move[0] == "d":
        return DISCARD + move[1]
    _, to, (kind, value) = move
    k = (to - g.current) % g.players - 1
    return HINT_N + k * 5 + value - 1 if kind == "n" else HINT_C + k * 6 + value


def main() -> None:
    games = json.loads((ROOT / "fixtures" / "coop_parity.json").read_text())[:60]
    out = []
    for g in games:
        env = CoopEnv(g["players"], seed=0)
        env.game = CoopGame(g["players"], parse_deck(g["deck"]))
        env.last = [None] * g["players"]
        steps = []
        for text in g["moves"]:
            o = env.observe()
            nz = np.flatnonzero(o)
            steps.append({"i": nz.tolist(), "v": np.round(o[nz], 6).tolist(), "mask": np.flatnonzero(env.legal_mask()).tolist()})
            action = encode(env, parse_move(text))
            assert env.legal_mask()[action], text
            env.step(action)
        out.append({"players": g["players"], "deck": g["deck"], "moves": g["moves"], "steps": steps})
    path = ROOT / "fixtures" / "selfplay_obs.json"
    path.write_text(json.dumps(out, separators=(",", ":")))
    print("wrote", path, sum(len(g["steps"]) for g in out), "observations")


if __name__ == "__main__":
    main()
