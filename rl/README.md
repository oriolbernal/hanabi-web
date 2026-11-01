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
- `distill.py` – trains the hint network to predict the value of every hint
  as measured by the search (`bin/label_hints.dart` writes the data). This
  is what the app ships now; see "Distilling the search" below.

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

Distillation (the model in the app):

```sh
(cd .. && dart run bin/label_hints.dart 200000 200400 32 rl/data/v4_0.jsonl v4)  # one of several in parallel
uv run python distill.py --data 'data/v4_*.jsonl' --out models/D.json --features v4
(cd .. && dart run bin/hint_eval.dart 2000 20000 --model=rl/models/D.json)
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

## A player agent

`train_player.py` trains the *player* (play / discard / ask for a hint) with
MaskablePPO against the app's hint policy (`hanabi/player_env.py`). It only
sees what a person would: hint information (also negative), the derived
probabilities, discard losses and the table. An oracle that sees its own
cards scores 23.9 (51% perfect games), so ~5 points are lost to imperfect
information.

Shaping with the reachable score must use Phi = 0 once the game is over:
the first try did not, and the agent learned to lose its lives on purpose to
dodge later penalties (~8 points instead of ~17).

2,000 fresh test games (`eval_player.py`), same decks for all, H_v3 hints:

| player | mean | ±95% |
|---|---|---|
| careful | 16.99 | 0.13 |
| cautious | 18.50 | 0.12 |
| balanced | 18.74 | 0.12 |
| bold | 18.79 | 0.13 |
| P3: PPO, no shaping | 19.51 | 0.13 |
| P4: PPO, shaping | **19.60** | 0.13 |

Alternating round (4,000 fresh test games): hints fine-tuned against a mix
with the agent (HA) and a second player seed (PB) give **20.16** (HA + PB,
now in the app), against 19.02 for the best rule-based player. Two seeds of
the same player training ended ~0.6 points apart (P4 vs PB).

## Distilling the search

The search hint mode (32 rollouts per hint, same cards for every hint) scores
21.5 but is slow. Instead of PPO, the network now learns to predict the value
the search measured for each hint (value regression, targets centered per
state), on games driven by the previous network (DAgger). Features **v4** add,
per hint, what the Expert rule player does right after it (play, discard,
ask; whether the play fits, whether the discard is free). Without them the
distilled network lost half a point to the Expert hint rules; with them:

| hints (2,000 fresh test games) | data | Expert player | human-like player |
|---|---|---|---|
| Expert hint rules | | 19.35 | 19.30 |
| HA + play-first rule (previous app model) | | 18.12 | |
| E3: PPO against Expert, v4, 3M steps | | 19.85 | 19.63 |
| D2: distilled, v4 | 95k hints | 19.99 | 19.75 |
| D3 | 189k | 20.18 | 19.96 |
| **D4** (in the app, no play-first rule) | 283k | **20.43** | **20.13** |

The player agent PB, trained with the HA hints, drops to 16.5 with D4 (the
Expert rules make 20.3 and the human-like ones 20.0, 2,000 games), so the app's
dev-mode advisor now follows the Expert rules instead of the agent.

Doubling the data is still worth ~0.2 points. A 512×512 network does not
beat 256×256; rounding weights to six decimals changes nothing (1.3 MB).

## The human-like player, fitted to the app's move log

`analyze_moves.py` rebuilds every state the app logged (dev mode, copy icon)
and compares the person's move with the simulated players'. Three games, 284
decisions: the person hints whenever a hint is left and discards only at zero,
plays uncertain cards from p ≥ 0.7 (13 of 13 fit; all five below 0.5 failed),
discards the oldest untouched card or a hinted card that no longer matters,
and never plays a joker whose number is unknown even when it fits every pile.
A grid search over the ExpertPlayer settings gives `human` = threshold 0.7,
reserve 1, chop discards, `joker_needs_number`:

| simulated player | same move as the person |
|---|---|
| Expert | 45% |
| old human (reserve 8, p ≥ 0.5) | 52% |
| **human** | **74%** |

Against this player the Expert hint rules score 17.92 and **D4 drops to 17.31**
(it was distilled from a search that simulated the Expert), while the search
simulating the human player makes 20.70 (100 games, +3.10). Labeling with
`label_hints ... --player=human` puts the human player both in the games and
inside the search rollouts, and the network distilled from that data wins:

| hints (2,000 test games) | human-like player | Expert player |
|---|---|---|
| Expert hint rules | 17.92 | 19.35 |
| D4 (distilled for the Expert) | 17.31 | 20.43 |
| **H1** (distilled for the human player, 82k hints) — in the app | **19.35** | 18.77 |

Each network is good for the player its search simulated and bad for the
other, so the app ships H1, its search mode simulates the human player and
the dev-mode advisor follows the human rules. D5 (D4's recipe with 377k
hints) made 20.51 with the Expert player: doubling the data is flattening out.
