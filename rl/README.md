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
uv run python -u train.py --name H_v3 --features v3 --players mixed --steps 3000000
uv run tensorboard --logdir runs              # learning curves
uv run python export.py models/H_v3.zip
(cd .. && dart run bin/players.dart 3000)        # every strategy × player
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
| B: + effect of each hint | v2 | 128×128 | 4M | 16.56 |
| C: bigger network | v2 | 256×256 | 4M | 16.56 |
| B + rule: obvious playable hint first | v2 | 128×128 | 4M | 16.62 |

Telling the network what each hint would do (v2) helped far more than
training longer or a bigger network.

### Hints a person would find silly

Playing it, B often skipped the obvious hint: with a 1 in the opening hand
it hinted "1" first only 43% of the time (lookahead: 100%). For the score it
does not matter, because asking for a hint costs the simulated player
nothing, so the order of hints is irrelevant to the reward.

Reward shaping did not fix it (1M steps, % of hints the player can act on
at once, B = 43.4%):

| run | change | eval | actionable |
|---|---|---|---|
| D | −0.2 reward per hint | 16.46 | 42.6% |
| E | gamma 0.9 | 16.50 | 43.1% |
| F | both | 16.62 | 43.6% |

What worked is a rule layer in `RlStrategy(playFirst: true)`: if some hint
lets the player play a card safely right now, only those are allowed and
the network picks among them. Score 16.62, first hint "1": 100%.


## Players that take risks

`CarefulPlayer` only acts when sure. `RiskTakingPlayer` estimates, from the
card distribution, discards, played cards and what hints revealed (also
negatively: "the other two are not green"), how likely each card is to fit
or to be useless, and plays above a threshold:

| profile | plays at | with one life | discards useless at |
|---|---|---|---|
| cautious | 90% | 100% | 100% |
| balanced | 75% | 95% | 90% |
| bold | 60% | 85% | 85% |

Lower discard thresholds always lost points (good cards thrown away).

Run G trains against a random profile each game (`--players mixed`).
Mean score, 3,000 games per cell, both with the playFirst rule:

| model | careful | cautious | balanced | bold |
|---|---|---|---|---|
| B (trained vs careful) | **16.69** | 16.13 | 16.66 | 16.93 |
| **G (mixed players)** | 16.58 | **16.60** | **17.18** | **17.42** |


## What is at stake: reachable score

`Game.maxScore()` is the best score still reachable given the discards, with
each unused joker filling one gap (losing one 5 costs nothing while the
joker 5 is around; losing a second costs a point). Where the ~8 missing
points went: ~6-7 by forced blind discards, ~1.6 by playing jokers where a
real card could still go.

Player changes: discard the card with the lowest *expected* loss of
reachable score, and do not play a known joker if that lowers it (choose
the pile where it helps most). Feature set v3 adds each card's discard loss
and the reachable score.

3,000 games per cell, all with the playFirst rule:

| model | careful | cautious | balanced | bold |
|---|---|---|---|---|
| lookahead | 15.83 | 18.44 | 18.71 | 18.86 |
| G (previous players) | **17.00** | 18.41 | 18.61 | 18.58 |
| H_v2 (new players) | 16.95 | 18.42 | 18.68 | 18.71 |
| **H_v3 (+ discard loss)** ← in the app | **17.04** | **18.51** | **18.79** | **18.88** |

Most of the jump (from ~16.6 to ~18.6) came from the smarter players; the
hint models now differ by tenths of a point.
