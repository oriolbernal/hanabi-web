# Hint policy with reinforcement learning

Trains the "partner" that chooses which hint to give, using PPO against the
careful simulated player from `lib/sim/simulated_player.dart`.

```
Dart rules ──export_parity.dart──▶ fixtures ──pytest──▶ Python port is exact
                                                        │
                       train.py (MaskablePPO) ◀─────────┘
                              │ models/hint_policy.zip
                       export.py
                              │ assets/models/hint_policy.json
                       RlStrategy (Dart) ──▶ bin/benchmark.dart, app
```

## Files

- `hanabi/game.py` – line-by-line port of the Dart rules and careful player.
- `hanabi/encoding.py` – observation (133 numbers) and the 11 actions. Must
  match `lib/sim/rl_strategy.dart`.
- `hanabi/env.py` – Gymnasium env: one step per hint; the player acts in
  between; reward = points scored.
- `train.py` – MaskablePPO (invalid hints are masked out), evaluates on 500
  fixed games every 50k steps and keeps the best model.
- `export.py` – writes the actor network as JSON for Dart.

## Run

```sh
cd rl
uv sync
(cd .. && dart run bin/export_parity.dart)   # reference games
uv run pytest                                 # Python == Dart?
uv run python -u train.py --name B_v2 --features v2 --steps 4000000
uv run tensorboard --logdir runs              # learning curves
uv run python export.py models/B_v2.zip
(cd .. && dart run bin/benchmark.dart 10000 --fast)
```

If you change the rules, the simulated player or the observation in Dart,
change the Python side too and rerun the parity test before training.

## Experiments so far

10,000 games in `bin/benchmark.dart` (Dart, seed 0):

| model | features | net | steps | mean |
|---|---|---|---|---|
| dummy (rule) | – | – | – | 13.63 |
| lookahead (hand-tuned) | – | – | – | 15.55 |
| first PPO run | v1 | 128×128 | 2M | 15.13 |
| A: same, trained longer | v1 | 128×128 | 6M | 15.80 |
| **B: + effect of each hint** | **v2** | **128×128** | **4M** | **16.56** ← in the app |
| C: bigger network | v2 | 256×256 | 4M | 16.56 |

Telling the network what each hint would do (v2) helped far more than
training longer or a bigger network.
