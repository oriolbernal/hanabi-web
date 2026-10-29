"""Train the hint policy with MaskablePPO.

    uv run python train.py --steps 2000000
    uv run tensorboard --logdir runs     # watch the curves
"""

import argparse
import random

import numpy as np
from sb3_contrib import MaskablePPO
from stable_baselines3.common.callbacks import BaseCallback
from stable_baselines3.common.vec_env import DummyVecEnv

from hanabi.encoding import action_mask, action_to_hint, encode
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


def policy_chooser(model):
    def choose(game: Game):
        action, _ = model.predict(encode(game), action_masks=action_mask(game), deterministic=True)
        return action_to_hint(int(action))

    return choose


class EvalCallback(BaseCallback):
    """Every `every` steps, plays the eval games and keeps the best model."""

    def __init__(self, every: int, path: str):
        super().__init__()
        self.every, self.path, self.best = every, path, -1.0

    def _on_step(self) -> bool:
        if self.num_timesteps % self.every < self.training_env.num_envs:
            score = np.mean([play(policy_chooser(self.model), s) for s in EVAL_SEEDS])
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
    parser.add_argument("--out", default="models/hint_policy")
    args = parser.parse_args()

    baseline = np.mean([play(dummy_hint, s) for s in EVAL_SEEDS])
    print(f"dummy on eval games: {baseline:.2f}")

    env = DummyVecEnv([HintEnv for _ in range(args.envs)])
    env.seed(args.seed)
    model = MaskablePPO(
        "MlpPolicy",
        env,
        n_steps=1024,
        batch_size=512,
        gamma=0.99,
        learning_rate=3e-4,
        ent_coef=0.01,
        policy_kwargs={"net_arch": {"pi": [128, 128], "vf": [128, 128]}},
        tensorboard_log="runs",
        seed=args.seed,
        verbose=0,
    )
    model.learn(args.steps, callback=EvalCallback(50_000, args.out), tb_log_name="ppo")


if __name__ == "__main__":
    main()
