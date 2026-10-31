"""Distill the hint search into a network: value regression.

The data comes from `bin/label_hints.dart`, one JSON line per hint asked:
{"o": "observation", "m": "legal-hint bits", "v": "average final score after
each hint"}. The network learns, for every legal hint, how much better or
worse than the average legal hint it is (the search's own estimate, which is
noisy per sample but unbiased, so the regression averages it out). Picking
the hint with the highest output then reproduces the search.

    uv run python distill.py --data 'data/hints_*.jsonl' --out models/D1.json
"""

import argparse
import glob
import json

import numpy as np
import torch
from torch import nn


def load(pattern: str):
    obs, masks, values = [], [], []
    for path in sorted(glob.glob(pattern)):
        with open(path) as f:
            for line in f:
                if not line.endswith("}\n"):
                    continue  # still being written
                d = json.loads(line)
                if d["m"].count("1") < 2:
                    continue  # nothing to choose
                obs.append(np.array(d["o"].split(), dtype=np.float32))
                masks.append(np.array([c == "1" for c in d["m"]]))
                values.append(np.array(d["v"].split(), dtype=np.float32))
    masks = torch.tensor(np.stack(masks))
    values = torch.tensor(np.stack(values))
    # Advantage over the average legal hint of the same state: the shuffles
    # are shared across hints, so differences are far less noisy than scores.
    mean = (values * masks).sum(1, keepdim=True) / masks.sum(1, keepdim=True)
    return torch.tensor(np.stack(obs)), masks, values - mean


def network(sizes: list[int]) -> nn.Sequential:
    layers: list[nn.Module] = []
    for i in range(len(sizes) - 1):
        layers.append(nn.Linear(sizes[i], sizes[i + 1]))
        if i < len(sizes) - 2:
            layers.append(nn.Tanh())
    return nn.Sequential(*layers)


def masked_mse(pred, target, masks):
    return (((pred - target) ** 2) * masks).sum() / masks.sum()


def report(net, obs, masks, adv) -> str:
    """Error, and how many points per hint the network's pick loses against
    the search's pick, as the search itself estimated them."""
    with torch.no_grad():
        pred = net(obs)
        mse = masked_mse(pred, adv, masks).item()
        pick = pred.masked_fill(~masks, -1e9).argmax(1)
        best = adv.masked_fill(~masks, -1e9).max(1).values
        regret = (best - adv.gather(1, pick[:, None])[:, 0]).mean().item()
        agree = (pick == adv.masked_fill(~masks, -1e9).argmax(1)).float().mean().item()
    return f"mse {mse:.3f}  regret {regret:.3f}  top-1 {agree:.3f}"


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--data", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--net", default="256,256", help="hidden layer sizes")
    p.add_argument("--epochs", type=int, default=30)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--weight-decay", type=float, default=1e-5)
    p.add_argument("--seed", type=int, default=0)
    args = p.parse_args()
    torch.manual_seed(args.seed)

    obs, masks, adv = load(args.data)
    n = len(obs)
    perm = torch.randperm(n, generator=torch.Generator().manual_seed(0))
    test, train = perm[: n // 10], perm[n // 10 :]
    hidden = [int(h) for h in args.net.split(",")]
    net = network([obs.shape[1], *hidden, masks.shape[1]])
    print(f"{n} hints, {obs.shape[1]} features, net {hidden}")
    # Regret of the average legal hint, for scale.
    with torch.no_grad():
        best = adv.masked_fill(~masks, -1e9).max(1).values
    print(f"regret of a random legal hint: {best[test].mean():.3f}")

    opt = torch.optim.AdamW(net.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, args.epochs)
    for epoch in range(args.epochs):
        order = train[torch.randperm(len(train))]
        for i in range(0, len(order), 512):
            b = order[i : i + 512]
            loss = masked_mse(net(obs[b]), adv[b], masks[b])
            opt.zero_grad()
            loss.backward()
            opt.step()
        sched.step()
        if epoch % 5 == 4 or epoch == args.epochs - 1:
            print(f"epoch {epoch + 1:3}: train [{report(net, obs[train], masks[train], adv[train])}]  "
                  f"test [{report(net, obs[test], masks[test], adv[test])}]")

    json.dump(
        {
            "agent": "hints",
            "features": "v3",
            "layers": [
                {"w": m.weight.detach().tolist(), "b": m.bias.detach().tolist()}
                for m in net
                if isinstance(m, nn.Linear)
            ],
        },
        open(args.out, "w"),
    )
    print("wrote", args.out)


if __name__ == "__main__":
    main()
