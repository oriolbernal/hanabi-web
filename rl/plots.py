"""Training curves for docs/rl.md, read from the TensorBoard logs in runs/.

    uv run python plots.py          # writes ../docs/img/*.png
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from tensorboard.backend.event_processing.event_accumulator import EventAccumulator

OUT = Path(__file__).parent.parent / "docs" / "img"

# Categorical slots in fixed order (validated light palette).
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]
SURFACE = "#fcfcfb"
TEXT = "#0b0b0b"
TEXT_2 = "#52514e"
MUTED = "#8a8985"
GRID = "#e7e6e2"


def scalars(run: str, tag: str = "eval/mean_score") -> tuple[np.ndarray, np.ndarray]:
    ea = EventAccumulator(f"runs/{run}", size_guidance={"scalars": 0})
    ea.Reload()
    if tag not in ea.Tags()["scalars"]:
        return np.array([]), np.array([])
    ev = ea.Scalars(tag)
    return np.array([e.step for e in ev]) / 1e6, np.array([e.value for e in ev])


def smooth(y: np.ndarray, k: int = 5) -> np.ndarray:
    """Trailing moving average, so each point only uses past evaluations."""
    return np.array([y[max(0, i - k + 1) : i + 1].mean() for i in range(len(y))])


def style(ax, title: str, ylabel: str) -> None:
    ax.set_facecolor(SURFACE)
    ax.set_title(title, loc="left", fontsize=12, color=TEXT, pad=10)
    ax.set_ylabel(ylabel, color=TEXT_2, fontsize=10)
    ax.set_xlabel("passos d'entrenament (milions)", color=TEXT_2, fontsize=10)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(GRID)
    ax.tick_params(colors=TEXT_2, labelsize=9)


def line(ax, x, y, color: str, label: str, raw: bool = True) -> None:
    if not len(x):
        return
    if raw:
        ax.plot(x, y, color=color, alpha=0.25, linewidth=1)
    ys = smooth(y)
    ax.plot(x, ys, color=color, linewidth=2, label=label)
    ax.__dict__.setdefault("end_labels", []).append((x[-1], ys[-1], label))


def place_end_labels(ax, gap: float = 0.055) -> None:
    """Direct labels at line ends, pushed apart so they never overlap."""
    items = sorted(ax.__dict__.get("end_labels", []), key=lambda t: t[1])
    lo, hi = ax.get_ylim()
    min_gap = gap * (hi - lo)
    placed: list[float] = []
    for _, y, _ in items:
        placed.append(max(y, placed[-1] + min_gap) if placed else y)
    for (x, y, label), ty in zip(items, placed):
        ax.annotate(
            label,
            (x, y),
            xytext=(x, ty),
            textcoords="data",
            va="center",
            fontsize=9,
            color=TEXT,
            annotation_clip=False,
        )
        ax.texts[-1].set_position((x + 0.01 * (ax.get_xlim()[1] - ax.get_xlim()[0]), ty))


def reference(ax, y: float, label: str) -> None:
    ax.axhline(y, color=MUTED, linewidth=1, linestyle=(0, (4, 3)))
    ax.annotate(label, (0, y), xytext=(2, 4), textcoords="offset points", fontsize=8, color=TEXT_2)


def figure(name: str, panels: int = 1, width: float = 8.5):
    fig, axes = plt.subplots(1, panels, figsize=(width, 4.2), facecolor=SURFACE)
    return fig, np.atleast_1d(axes)


def save(fig, name: str) -> None:
    for ax in fig.axes:
        place_end_labels(ax)
    fig.tight_layout()
    fig.savefig(OUT / name, dpi=150, facecolor=SURFACE)
    plt.close(fig)
    print("wrote", OUT / name)


def hint_features() -> None:
    fig, (ax,) = figure("hints")
    x1, y1 = scalars("ppo_2")
    x2, y2 = scalars("A_more_0")
    line(ax, np.r_[x1, x2], np.r_[y1, y2], SERIES[0], "v1, 128×128 (A: fins a 6M)")
    line(ax, *scalars("B_v2_1"), SERIES[1], "v2, 128×128 (B)")
    line(ax, *scalars("C_v2_big_1"), SERIES[2], "v2, 256×256 (C)")
    reference(ax, 13.60, "dummy (13,6)")
    style(ax, "IA de pistes: què l'ha fet millorar", "puntuació mitjana (500 partides)")
    ax.set_ylim(12, 17.5)
    ax.set_xlim(0, 7.6)
    ax.legend(loc="lower right", frameon=False, fontsize=9)
    save(fig, "hints_features.png")


def reward_shaping() -> None:
    fig, (a, b) = figure("shaping", panels=2, width=10)
    runs = [("D_cost_1", "D: cost per pista"), ("E_gamma_1", "E: gamma 0,9"), ("F_both_1", "F: tots dos")]
    for (run, label), color in zip(runs, SERIES):
        line(a, *scalars(run), color, label)
        x, y = scalars(run, "eval/actionable_rate")
        line(b, x, y * 100, color, label)
    style(a, "Puntuació", "puntuació mitjana")
    style(b, "Pistes accionables", "% de pistes")
    b.axhline(43.4, color=MUTED, linewidth=1, linestyle=(0, (4, 3)))
    b.annotate("model B: 43,4%", (0, 43.4), xytext=(2, 4), textcoords="offset points", fontsize=8, color=TEXT_2)
    for ax in (a, b):
        ax.set_xlim(0, 1.45)
    a.legend(loc="lower right", frameon=False, fontsize=9)
    save(fig, "reward_shaping.png")


def player_features() -> None:
    fig, (ax,) = figure("v3")
    line(ax, *scalars("H_v2_1"), SERIES[0], "H_v2")
    line(ax, *scalars("H_v3_1"), SERIES[1], "H_v3 (+ punts en joc)")
    style(ax, "IA de pistes amb jugadors que arrisquen", "puntuació mitjana (4 perfils)")
    ax.set_xlim(0, 3.7)
    ax.legend(loc="lower right", frameon=False, fontsize=9)
    save(fig, "hints_v2_vs_v3.png")


def player_agent() -> None:
    fig, (ax,) = figure("agent")
    line(ax, *scalars("P1_1"), SERIES[0], "P1: shaping amb error", raw=False)
    line(ax, *scalars("P2_1"), SERIES[3], "P2: el mateix, altra llavor", raw=False)
    line(ax, *scalars("P3_1"), SERIES[1], "P3: sense shaping")
    line(ax, *scalars("P4_1"), SERIES[2], "P4: shaping corregit")
    reference(ax, 18.86, "jugador bold (18,9)")
    style(ax, "Agent jugador (PPO)", "puntuació mitjana (200 partides)")
    ax.set_xlim(0, 6.3)
    ax.legend(loc="lower right", frameon=False, fontsize=9)
    save(fig, "player_agent.png")


def player_seeds() -> None:
    fig, (ax,) = figure("seeds")
    x1, y1 = scalars("P4_1")
    x2, y2 = scalars("PA_0")
    # PA resumed from P4's best checkpoint, not from its last step.
    keep = x1 < x2[0]
    line(ax, np.r_[x1[keep], x2], np.r_[y1[keep], y2], SERIES[0], "P4 → PA (continua)")
    line(ax, *scalars("PB_1"), SERIES[1], "PB (llavor nova)")
    reference(ax, 18.86, "jugador bold (18,9)")
    style(ax, "Agent jugador: més temps i una altra llavor", "puntuació mitjana (200 partides)")
    ax.set_ylim(10, 21)
    ax.set_xlim(0, 11.8)
    ax.legend(loc="lower right", frameon=False, fontsize=9)
    save(fig, "player_seeds.png")


def hints_for_agent() -> None:
    fig, (ax,) = figure("ha")
    line(ax, *scalars("HA_0"), SERIES[0], "HA (parteix d'H_v3)")
    style(ax, "IA de pistes afinada amb l'agent jugador", "puntuació mitjana (perfils + agent)")
    ax.set_xlim(2.9, 6.9)
    ax.set_ylim(18, 20)
    save(fig, "hints_for_agent.png")


def ppo_internals() -> None:
    fig, (a, b) = figure("internals", panels=2, width=10)
    x, y = scalars("P4_1", "train/entropy_loss")
    line(a, x, -y, SERIES[0], "P4", raw=False)
    x, y = scalars("P4_1", "train/explained_variance")
    line(b, x, y, SERIES[0], "P4", raw=False)
    style(a, "Entropia de la política", "entropia (nats)")
    style(b, "Variància explicada pel crític", "0 = res, 1 = tot")
    b.set_ylim(0, 1)
    save(fig, "ppo_internals.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    hint_features()
    reward_shaping()
    player_features()
    player_agent()
    player_seeds()
    hints_for_agent()
    ppo_internals()
