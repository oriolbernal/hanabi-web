"""Train a player agent (play / discard / ask) with MaskablePPO against a
fixed hint policy.

    uv run python -u train_player.py --name P1 --shaping 1.0 --seed 0
"""

import argparse
import json
import random
from pathlib import Path

import numpy as np
import torch
from sb3_contrib import MaskablePPO
from stable_baselines3.common.callbacks import BaseCallback
from stable_baselines3.common.vec_env import DummyVecEnv

from hanabi.game import PLAYERS, Game, apply_move, build_deck
from hanabi.hint_policy import HintPolicy
from hanabi.player_env import PlayerEnv, apply_player_action, encode_player, player_mask

EVAL_SEEDS = range(2_000_000, 2_000_200)


def play_agent(model, hints: HintPolicy, seed: int) -> int:
    game = Game(build_deck(random.Random(seed)))
    while not game.is_over:
        action, _ = model.predict(encode_player(game), action_masks=player_mask(game), deterministic=True)
        apply_player_action(game, int(action), hints)
    return game.score


def play_profile(name: str, hints: HintPolicy, seed: int) -> int:
    game, player = Game(build_deck(random.Random(seed))), PLAYERS[name]
    while not game.is_over:
        move = player(game)
        if move[0] == "hint":
            game.hints -= 1
            game.apply_hint(hints(game))
        else:
            apply_move(game, move)
    return game.score


class EvalCallback(BaseCallback):
    def __init__(self, every: int, path: str, hints: HintPolicy):
        super().__init__()
        self.every, self.path, self.hints, self.best = every, path, hints, -1.0

    def _on_step(self) -> bool:
        if self.num_timesteps % self.every < self.training_env.num_envs:
            score = np.mean([play_agent(self.model, self.hints, s) for s in EVAL_SEEDS])
            self.logger.record("eval/mean_score", score)
            if score > self.best:
                self.best = score
                self.model.save(self.path)
            print(f"step {self.num_timesteps:>9,}: eval {score:.2f} (best {self.best:.2f})")
        return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    parser.add_argument("--steps", type=int, default=5_000_000)
    parser.add_argument("--envs", type=int, default=8)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--shaping", type=float, default=1.0)
    parser.add_argument("--hints", default="../assets/models/hint_policy.json")
    parser.add_argument("--net", default="256,256")
    parser.add_argument("--resume", help="continue training a saved model")
    parser.add_argument(
        "--no-wasted-discards",
        action="store_true",
        help="mask discards with every hint token in hand, as the app does",
    )
    args = parser.parse_args()

    torch.set_num_threads(1)
    Path("models").mkdir(exist_ok=True)
    out = f"models/{args.name}"
    Path(f"{out}.json").write_text(json.dumps({"agent": "player", "features": "p1"}))

    hints = HintPolicy(args.hints)
    baseline = np.mean([play_profile("bold", hints, s) for s in EVAL_SEEDS])
    print(f"bold player on eval games: {baseline:.2f}")

    env = DummyVecEnv(
        [
            lambda: PlayerEnv(args.hints, args.shaping, no_wasted_discards=args.no_wasted_discards)
            for _ in range(args.envs)
        ]
    )
    env.seed(args.seed)
    callback = EvalCallback(100_000, out, hints)
    if args.resume:
        model = MaskablePPO.load(args.resume, env=env, tensorboard_log="runs")
        model.learn(args.steps, callback=callback, tb_log_name=args.name, reset_num_timesteps=False)
        return

    hidden = [int(n) for n in args.net.split(",")]
    model = MaskablePPO(
        "MlpPolicy",
        env,
        n_steps=1024,
        batch_size=1024,
        gamma=0.99,
        learning_rate=3e-4,
        ent_coef=0.01,
        policy_kwargs={"net_arch": {"pi": hidden, "vf": hidden}},
        tensorboard_log="runs",
        seed=args.seed,
        verbose=0,
    )
    model.learn(args.steps, callback=callback, tb_log_name=args.name)


if __name__ == "__main__":
    main()
