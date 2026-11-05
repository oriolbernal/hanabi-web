"""Distill the co-op search into a network that scores candidate moves.

The data comes from `bin/coop_label.dart`, one JSON line per bot move:
{"s": state features, "c": [features of each candidate move], "v": the
search's average final score after each candidate}. The network reads the
state and one candidate and predicts how much better than the average
candidate of that state it is; the bot (lib/sim/coop_net.dart) plays the
candidate with the highest output.

    uv run python coop_distill.py --data 'data/coop/c1a_*.jsonl' --out models/C1.json
"""

import argparse
import glob
import json

import numpy as np
import torch
from torch import nn


def _lines(pattern: str):
    for path in sorted(glob.glob(pattern)):
        with open(path) as f:
            for line in f:
                if line.endswith("}\n"):  # skip a line still being written
                    yield line


def load(pattern: str):
    """Two passes, so the arrays are allocated once; candidates are kept in
    float16 (the features are probabilities and small counts), which halves
    the memory for a million moves."""
    n = k = 0
    s_size = m_size = 0
    for line in _lines(pattern):
        d = json.loads(line)
        n += 1
        k = max(k, len(d["c"]))
        if not s_size:
            s_size = len(d["s"].split())
            m_size = len(d["c"][0].split())
    states = np.zeros((n, s_size), dtype=np.float32)
    c = np.zeros((n, k, m_size), dtype=np.float16)
    v = np.zeros((n, k), dtype=np.float32)
    mask = np.zeros((n, k), dtype=bool)
    for i, line in enumerate(_lines(pattern)):
        if i >= n:
            break
        d = json.loads(line)
        states[i] = np.array(d["s"].split(), dtype=np.float32)
        for j, cand in enumerate(d["c"]):
            c[i, j] = np.array(cand.split(), dtype=np.float32)
        vs = np.array(d["v"].split(), dtype=np.float32)
        v[i, : len(vs)] = vs
        mask[i, : len(vs)] = True
    v = torch.tensor(v)
    mask = torch.tensor(mask)
    mean = (v * mask).sum(1, keepdim=True) / mask.sum(1, keepdim=True)
    return torch.tensor(states), torch.tensor(c), mask, (v - mean) * mask


class Scorer(nn.Module):
    """One tanh MLP applied to [state, candidate] for every candidate."""

    def __init__(self, sizes: list[int]):
        super().__init__()
        layers: list[nn.Module] = []
        for i in range(len(sizes) - 1):
            layers.append(nn.Linear(sizes[i], sizes[i + 1]))
            if i < len(sizes) - 2:
                layers.append(nn.Tanh())
        self.net = nn.Sequential(*layers)

    def forward(self, states, cands):
        cands = cands.float()
        s = states[:, None, :].expand(-1, cands.shape[1], -1)
        return self.net(torch.cat([s, cands], dim=2))[..., 0]


def masked_mse(pred, target, mask):
    return (((pred - target) ** 2) * mask).sum() / mask.sum()


def report(net, s, c, mask, adv) -> str:
    with torch.no_grad():
        # In chunks: the whole set at once would need gigabytes.
        pred = torch.cat([net(s[i : i + 65536], c[i : i + 65536]) for i in range(0, len(s), 65536)])
        mse = masked_mse(pred, adv, mask).item()
        pick = pred.masked_fill(~mask, -1e9).argmax(1)
        best = adv.masked_fill(~mask, -1e9).max(1).values
        regret = (best - adv.gather(1, pick[:, None])[:, 0]).mean().item()
        agree = (pick == adv.masked_fill(~mask, -1e9).argmax(1)).float().mean().item()
    return f"mse {mse:.3f}  regret {regret:.3f}  top-1 {agree:.3f}"


def rounded(t: torch.Tensor) -> list:
    return np.round(t.detach().double().numpy(), 6).tolist()


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--data", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--net", default="256,256", help="hidden layer sizes")
    p.add_argument("--epochs", type=int, default=30)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--weight-decay", type=float, default=1e-5)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--features", default="c3")
    p.add_argument("--moves", default="shortlist", help="'all' if every legal move was scored")
    args = p.parse_args()
    torch.manual_seed(args.seed)

    s, c, mask, adv = load(args.data)
    n = len(s)
    perm = torch.randperm(n, generator=torch.Generator().manual_seed(0))
    test, train = perm[: n // 10], perm[n // 10 :]
    hidden = [int(h) for h in args.net.split(",")]
    net = Scorer([s.shape[1] + c.shape[2], *hidden, 1])
    print(f"{n} moves, up to {c.shape[1]} candidates, {s.shape[1]}+{c.shape[2]} features, net {hidden}")
    with torch.no_grad():
        best = adv.masked_fill(~mask, -1e9).max(1).values
    print(f"regret of the average candidate: {best[test].mean():.3f}")

    opt = torch.optim.AdamW(net.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, args.epochs)
    for epoch in range(args.epochs):
        order = train[torch.randperm(len(train))]
        for i in range(0, len(order), 512):
            b = order[i : i + 512]
            loss = masked_mse(net(s[b], c[b]), adv[b], mask[b])
            opt.zero_grad()
            loss.backward()
            opt.step()
        sched.step()
        if epoch % 5 == 4 or epoch == args.epochs - 1:
            print(f"epoch {epoch + 1:3}: train [{report(net, s[train], c[train], mask[train], adv[train])}]  "
                  f"test [{report(net, s[test], c[test], mask[test], adv[test])}]")

    json.dump(
        {
            "agent": "coop",
            "features": args.features,
            "moves": args.moves,
            "layers": [
                {"w": rounded(m.weight), "b": rounded(m.bias)}
                for m in net.net
                if isinstance(m, nn.Linear)
            ],
        },
        open(args.out, "w"),
        separators=(",", ":"),
    )
    print("wrote", args.out)


if __name__ == "__main__":
    main()
