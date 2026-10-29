"""Train the hint policy with MaskablePPO.

    uv run python -u train.py --steps 2000000
    uv run python -u train.py --name v2 --features v2 --net 256,256
    uv run python -u train.py --name more --resume models/hint_policy.zip
    uv run tensorboard --logdir runs     # watch the curves
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

from hanabi.encoding import ENCODERS, action_mask, action_to_hint
from hanabi.env import HintEnv
from hanabi.game import Game, apply_move, build_deck, careful_move, dummy_hint

EVAL_SEEDS = range(1_000_000, 1_000_500)


def play(choose_hint, seed: int) -> int:
    """One full game on a fixed deck with the given hint chooser."""
    game = Game(build_deck(random.Random(seed)))
    while not game.is_over:
        move = careful_move(game)
        if move[0] == "hint":
            game.hints -= 1
            game.apply_hint(choose_hint(game))
        else:
            apply_move(game, move)
    return game.score


def policy_chooser(model, encode):
    def choose(game: Game):
        action, _ = model.predict(encode(game), action_masks=action_mask(game), deterministic=True)
        return action_to_hint(int(action))

    return choose


class EvalCallback(BaseCallback):
    """Every `every` steps, plays the eval games and keeps the best model."""

    def __init__(self, every: int, path: str, encode):
        super().__init__()
        self.every, self.path, self.encode, self.best = every, path, encode, -1.0

    def _on_step(self) -> bool:
        if self.num_timesteps % self.every < self.training_env.num_envs:
            score = np.mean([play(policy_chooser(self.model, self.encode), s) for s in EVAL_SEEDS])
            self.logger.record("eval/mean_score", score)
            if score > self.best:
                self.best = score
                self.model.save(self.path)
            print(f"step {self.num_timesteps:>9,}: eval {score:.2f} (best {self.best:.2f})")
        return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--steps", type=int, default=2_000_000)
    parser.add_argument("--envs", type=int, default=8)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--name", default="hint_policy")
    parser.add_argument("--features", choices=ENCODERS, default="v1")
    parser.add_argument("--net", default="128,128", help="hidden layer sizes")
    parser.add_argument("--resume", help="continue training a saved model")
    args = parser.parse_args()

    # One core per run, so several experiments can train side by side.
    torch.set_num_threads(1)
    out = f"models/{args.name}"
    Path("models").mkdir(exist_ok=True)
    Path(f"{out}.json").write_text(json.dumps({"features": args.features}))

    baseline = np.mean([play(dummy_hint, s) for s in EVAL_SEEDS])
    print(f"dummy on eval games: {baseline:.2f}")

    env = DummyVecEnv([lambda: HintEnv(args.features) for _ in range(args.envs)])
    env.seed(args.seed)
    if args.resume:
        model = MaskablePPO.load(args.resume, env=env, tensorboard_log="runs")
        model.learn(
            args.steps,
            callback=EvalCallback(50_000, out, ENCODERS[args.features][0]),
            tb_log_name=args.name,
            reset_num_timesteps=False,
        )
        return

    hidden = [int(n) for n in args.net.split(",")]
    model = MaskablePPO(
        "MlpPolicy",
        env,
        n_steps=1024,
        batch_size=512,
        gamma=0.99,
        learning_rate=3e-4,
        ent_coef=0.01,
        policy_kwargs={"net_arch": {"pi": hidden, "vf": hidden}},
        tensorboard_log="runs",
        seed=args.seed,
        verbose=0,
    )
    model.learn(
        args.steps,
        callback=EvalCallback(50_000, out, ENCODERS[args.features][0]),
        tb_log_name=args.name,
    )


if __name__ == "__main__":
    main()
