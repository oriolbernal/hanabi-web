"""Compare trained player agents with the rule-based profiles on fresh games.

    uv run python eval_player.py models/P3.zip models/P4.zip --games 2000
"""

import argparse
from multiprocessing import Pool

import numpy as np
from sb3_contrib import MaskablePPO

from hanabi.game import PLAYERS
from hanabi.hint_policy import HintPolicy
from train_player import play_agent, play_profile

TEST_SEEDS = 3_000_000  # never used for training or model selection
HINTS = "../assets/models/hint_policy.json"


def run(job):
    kind, name, start, n, hints_path = job
    hints = HintPolicy(hints_path)
    if kind == "agent":
        model = MaskablePPO.load(name, device="cpu")
        return [play_agent(model, hints, s) for s in range(start, start + n)]
    return [play_profile(name, hints, s) for s in range(start, start + n)]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("models", nargs="*")
    parser.add_argument("--games", type=int, default=2000)
    parser.add_argument("--hints", default=HINTS, help="exported hint policy (JSON)")
    args = parser.parse_args()

    entries = [("profile", p) for p in PLAYERS] + [("agent", m) for m in args.models]
    chunk = args.games // 8
    jobs = [(k, n, TEST_SEEDS + i * chunk, chunk, args.hints) for k, n in entries for i in range(8)]
    with Pool(8) as pool:
        results = pool.map(run, jobs)
    print(f"{args.games} test games each (same decks for all), hints: {args.hints}\n")
    print("player            mean   ±95%   perfect")
    for e, (kind, name) in enumerate(entries):
        scores = np.concatenate(results[e * 8 : (e + 1) * 8])
        margin = 1.96 * scores.std() / np.sqrt(len(scores))
        print(f"{name:<16} {scores.mean():6.2f}  {margin:5.2f}  {np.mean(scores == 25):6.1%}")


if __name__ == "__main__":
    main()
