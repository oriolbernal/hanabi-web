"""Imitation learning (DAgger): teach a network the teachers' choices.

The data comes from `bin/label.dart`, one JSON line per decision:
{"o": "observation as space-separated numbers", "m": "legal-action bits",
 "a": teacher's action}. Training starts from the current exported network
(the same JSON the app loads) and writes the result in that format.

    uv run python imitate.py --init ../assets/models/player_policy.json \\
        --data 'data/*_player_*.jsonl' --out models/IP1.json
"""

import argparse
import glob
import json

import numpy as np
import torch
from torch import nn


def load(pattern: str):
    obs, masks, actions = [], [], []
    for path in sorted(glob.glob(pattern)):
        with open(path) as f:
            for line in f:
                d = json.loads(line)
                obs.append(np.array(d["o"].split(), dtype=np.float32))
                masks.append(np.array([c == "1" for c in d["m"]]))
                actions.append(d["a"])
    return (
        torch.tensor(np.stack(obs)),
        torch.tensor(np.stack(masks)),
        torch.tensor(actions),
    )


def network(init: dict) -> nn.Sequential:
    layers: list[nn.Module] = []
    for i, l in enumerate(init["layers"]):
        w = torch.tensor(l["w"], dtype=torch.float32)
        linear = nn.Linear(w.shape[1], w.shape[0])
        with torch.no_grad():
            linear.weight.copy_(w)
            linear.bias.copy_(torch.tensor(l["b"], dtype=torch.float32))
        layers.append(linear)
        if i < len(init["layers"]) - 1:
            layers.append(nn.Tanh())
    return nn.Sequential(*layers)


def accuracy(net, obs, masks, actions) -> float:
    with torch.no_grad():
        logits = net(obs).masked_fill(~masks, -1e9)
        return (logits.argmax(1) == actions).float().mean().item()


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--init", required=True)
    p.add_argument("--data", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--epochs", type=int, default=20)
    p.add_argument("--lr", type=float, default=3e-4)
    args = p.parse_args()

    init = json.load(open(args.init))
    obs, masks, actions = load(args.data)
    n = len(actions)
    perm = torch.randperm(n, generator=torch.Generator().manual_seed(0))
    test = perm[: n // 10]
    train = perm[n // 10 :]
    net = network(init)
    print(f"{n} decisions; agreement with the teacher before: "
          f"{accuracy(net, obs[test], masks[test], actions[test]):.3f}")

    opt = torch.optim.Adam(net.parameters(), lr=args.lr)
    loss_fn = nn.CrossEntropyLoss()
    for epoch in range(args.epochs):
        order = train[torch.randperm(len(train))]
        for i in range(0, len(order), 256):
            b = order[i : i + 256]
            logits = net(obs[b]).masked_fill(~masks[b], -1e9)
            loss = loss_fn(logits, actions[b])
            opt.zero_grad()
            loss.backward()
            opt.step()
        if epoch % 5 == 4 or epoch == args.epochs - 1:
            print(f"epoch {epoch + 1}: train {accuracy(net, obs[train], masks[train], actions[train]):.3f} "
                  f"test {accuracy(net, obs[test], masks[test], actions[test]):.3f}")

    out = {k: v for k, v in init.items() if k != "layers"}
    out["layers"] = [
        {"w": m.weight.detach().tolist(), "b": m.bias.detach().tolist()}
        for m in net
        if isinstance(m, nn.Linear)
    ]
    json.dump(out, open(args.out, "w"))
    print("wrote", args.out)


if __name__ == "__main__":
    main()
