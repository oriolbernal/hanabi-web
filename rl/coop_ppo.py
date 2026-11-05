"""Self-play PPO for the co-op game: one network plays every seat.

Workers play many games at once with a copy of the network and send back
what happened; the learner updates the network with PPO and sends the new
weights. The only signal is the team's score (points added per move): no
hand-made rule says what is a good hint or when a 5 may go.

    uv run python coop_ppo.py --out runs/sp1 --workers 8 --hours 2

Every --eval-every updates it plays 300 fixed games per number of players
with the most likely move and logs the mean score and the share of 25s.
"""

from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import os
import time
from pathlib import Path

import numpy as np
import torch
from torch import nn

from hanabi.coop_env import N_ACTIONS, OBS_SIZE, CoopEnv


class Net(nn.Module):
    def __init__(self, hidden: int = 512) -> None:
        super().__init__()
        self.body = nn.Sequential(
            nn.Linear(OBS_SIZE, hidden), nn.ReLU(),
            nn.Linear(hidden, hidden), nn.ReLU(),
            nn.Linear(hidden, hidden), nn.ReLU(),
        )
        self.pi = nn.Linear(hidden, N_ACTIONS)
        self.v = nn.Linear(hidden, 1)

    def forward(self, obs, mask):
        h = self.body(obs)
        logits = self.pi(h).masked_fill(~mask, -1e9)
        return logits, self.v(h)[..., 0]


def worker(conn, seed: int, envs: int, steps: int, hidden: int) -> None:
    torch.set_num_threads(1)
    rng = np.random.default_rng(seed)
    net = Net(hidden)
    games = [CoopEnv(int(rng.integers(2, 5)), seed=seed * 1000 + i) for i in range(envs)]
    finished: list[tuple[int, int]] = []
    while True:
        msg = conn.recv()
        if msg is None:
            return
        net.load_state_dict(msg)
        obs = np.zeros((steps, envs, OBS_SIZE), dtype=np.float16)
        mask = np.zeros((steps, envs, N_ACTIONS), dtype=bool)
        act = np.zeros((steps, envs), dtype=np.int64)
        logp = np.zeros((steps, envs), dtype=np.float32)
        val = np.zeros((steps, envs), dtype=np.float32)
        rew = np.zeros((steps, envs), dtype=np.float32)
        done = np.zeros((steps, envs), dtype=bool)
        for t in range(steps):
            o = np.stack([g.observe() for g in games])
            m = np.stack([g.legal_mask() for g in games])
            with torch.no_grad():
                logits, v = net(torch.from_numpy(o), torch.from_numpy(m))
                dist = torch.distributions.Categorical(logits=logits)
                a = dist.sample()
                lp = dist.log_prob(a)
            obs[t], mask[t], act[t], logp[t], val[t] = o, m, a.numpy(), lp.numpy(), v.numpy()
            for i, g in enumerate(games):
                r, over = g.step(int(a[i]))
                rew[t, i] = r
                if over:
                    done[t, i] = True
                    finished.append((g.players, g.game.score))
                    g.players = int(rng.integers(2, 5))
                    g.reset()
        o = np.stack([g.observe() for g in games])
        m = np.stack([g.legal_mask() for g in games])
        with torch.no_grad():
            _, last_v = net(torch.from_numpy(o), torch.from_numpy(m))
        conn.send((obs, mask, act, logp, val, rew, done, last_v.numpy(), finished))
        finished = []


def gae(rew, val, done, last_v, gamma, lam):
    steps = rew.shape[0]
    adv = np.zeros_like(rew)
    running = np.zeros_like(last_v)
    for t in reversed(range(steps)):
        nxt = last_v if t == steps - 1 else val[t + 1]
        nonterminal = 1.0 - done[t]
        delta = rew[t] + gamma * nxt * nonterminal - val[t]
        running = delta + gamma * lam * nonterminal * running
        adv[t] = running
    return adv, adv + val


def evaluate(net: Net, games: int = 300) -> dict[int, tuple[float, float]]:
    """Greedy play on fixed decks: (mean score, share of 25s) per players."""
    net = net.cpu().eval()
    out = {}
    for players in (2, 3, 4):
        envs = [CoopEnv(players, seed=10_000_000 + players * 100_000 + i) for i in range(games)]
        live = list(range(games))
        while live:
            o = torch.from_numpy(np.stack([envs[i].observe() for i in live]))
            m = torch.from_numpy(np.stack([envs[i].legal_mask() for i in live]))
            with torch.no_grad():
                a = net(o, m)[0].argmax(-1).numpy()
            nxt = []
            for j, i in enumerate(live):
                _, over = envs[i].step(int(a[j]))
                if not over:
                    nxt.append(i)
            live = nxt
        scores = np.array([e.game.score for e in envs])
        out[players] = (float(scores.mean()), float((scores == 25).mean()))
    net.train()
    return out


def export(net: Net, path: Path) -> None:
    layers = [m for m in net.body if isinstance(m, nn.Linear)] + [net.pi]
    json.dump(
        {
            "agent": "coop-selfplay",
            "obs": OBS_SIZE,
            "actions": N_ACTIONS,
            "layers": [
                {"w": np.round(m.weight.detach().cpu().double().numpy(), 6).tolist(),
                 "b": np.round(m.bias.detach().cpu().double().numpy(), 6).tolist()}
                for m in layers
            ],
        },
        open(path, "w"),
        separators=(",", ":"),
    )


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--workers", type=int, default=8)
    p.add_argument("--envs", type=int, default=32)
    p.add_argument("--steps", type=int, default=128)
    p.add_argument("--hidden", type=int, default=512)
    p.add_argument("--lr", type=float, default=3e-4)
    p.add_argument("--gamma", type=float, default=0.999)
    p.add_argument("--lam", type=float, default=0.95)
    p.add_argument("--clip", type=float, default=0.2)
    p.add_argument("--epochs", type=int, default=2)
    p.add_argument("--minibatch", type=int, default=4096)
    p.add_argument("--entropy", type=float, default=0.01)
    p.add_argument("--hours", type=float, default=1.0)
    p.add_argument("--eval-every", type=int, default=25)
    p.add_argument("--resume")
    p.add_argument("--device", default="mps" if torch.backends.mps.is_available() else "cpu")
    args = p.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    torch.manual_seed(0)

    net = Net(args.hidden)
    if args.resume:
        net.load_state_dict(torch.load(args.resume))
    net.to(args.device)
    opt = torch.optim.Adam(net.parameters(), lr=args.lr, eps=1e-5)

    ctx = mp.get_context("spawn")
    pipes = []
    procs = []
    for w in range(args.workers):
        a, b = ctx.Pipe()
        proc = ctx.Process(target=worker, args=(b, w + 1, args.envs, args.steps, args.hidden), daemon=True)
        proc.start()
        pipes.append(a)
        procs.append(proc)

    log = open(out / "log.txt", "a")
    start = time.time()
    total_steps = 0
    update = 0
    best = -1.0
    recent: list[tuple[int, int]] = []
    while time.time() - start < args.hours * 3600:
        weights = {k: v.detach().cpu() for k, v in net.state_dict().items()}
        for c in pipes:
            c.send(weights)
        parts = [c.recv() for c in pipes]
        obs = np.concatenate([x[0] for x in parts], axis=1)
        mask = np.concatenate([x[1] for x in parts], axis=1)
        act = np.concatenate([x[2] for x in parts], axis=1)
        logp = np.concatenate([x[3] for x in parts], axis=1)
        val = np.concatenate([x[4] for x in parts], axis=1)
        rew = np.concatenate([x[5] for x in parts], axis=1)
        done = np.concatenate([x[6] for x in parts], axis=1)
        last_v = np.concatenate([x[7] for x in parts])
        for x in parts:
            recent += x[8]
        recent = recent[-3000:]
        adv, ret = gae(rew, val, done, last_v, args.gamma, args.lam)

        n = obs.shape[0] * obs.shape[1]
        total_steps += n
        t_obs = torch.from_numpy(obs.reshape(n, -1).astype(np.float32)).to(args.device)
        t_mask = torch.from_numpy(mask.reshape(n, -1)).to(args.device)
        t_act = torch.from_numpy(act.reshape(n)).to(args.device)
        t_logp = torch.from_numpy(logp.reshape(n)).to(args.device)
        t_adv = torch.from_numpy(adv.reshape(n)).to(args.device)
        t_ret = torch.from_numpy(ret.reshape(n)).to(args.device)
        t_adv = (t_adv - t_adv.mean()) / (t_adv.std() + 1e-8)
        for _ in range(args.epochs):
            perm = torch.randperm(n, device=args.device)
            for i in range(0, n, args.minibatch):
                b = perm[i : i + args.minibatch]
                logits, v = net(t_obs[b], t_mask[b])
                dist = torch.distributions.Categorical(logits=logits)
                ratio = (dist.log_prob(t_act[b]) - t_logp[b]).exp()
                pg = -torch.min(ratio * t_adv[b], ratio.clamp(1 - args.clip, 1 + args.clip) * t_adv[b]).mean()
                vloss = ((v - t_ret[b]) ** 2).mean()
                ent = dist.entropy().mean()
                loss = pg + 0.5 * vloss - args.entropy * ent
                opt.zero_grad()
                loss.backward()
                nn.utils.clip_grad_norm_(net.parameters(), 0.5)
                opt.step()
        update += 1

        by = {k: [s for pl, s in recent if pl == k] for k in (2, 3, 4)}
        line = (
            f"upd {update} steps {total_steps / 1e6:.1f}M {total_steps / (time.time() - start):.0f}/s "
            + " ".join(f"{k}p {np.mean(v):.1f}" for k, v in by.items() if v)
            + f" ent {ent.item():.2f} v {vloss.item():.2f}"
        )
        if update % args.eval_every == 0:
            ev = evaluate(net)
            net.to(args.device)
            line += " | eval " + " ".join(f"{k}p {m:.2f} ({100 * s:.0f}% 25)" for k, (m, s) in ev.items())
            mean = float(np.mean([m for m, _ in ev.values()]))
            torch.save(net.state_dict(), out / "last.pt")
            if mean > best:
                best = mean
                torch.save(net.state_dict(), out / "best.pt")
                export(net, out / "best.json")
        print(line, flush=True)
        log.write(line + "\n")
        log.flush()
    for c in pipes:
        c.send(None)
    for proc in procs:
        proc.join(timeout=5)


if __name__ == "__main__":
    os.environ.setdefault("OMP_NUM_THREADS", "1")
    main()
