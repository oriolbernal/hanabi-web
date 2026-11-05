"""Exports a self-play network (coop_ppo.py) for the app: the policy only,
weights as int16 with one scale per row (lib/sim/mlp.dart reads them), and
checks the rounded network plays as well as the original.

    uv run python export_selfplay.py runs/sp1/best.pt ../assets/models/coop_selfplay.json
"""

import argparse
import base64
import json

import numpy as np
import torch
from torch import nn

from coop_ppo import Net, evaluate
from hanabi.coop_env import N_ACTIONS, OBS_SIZE


def quantize(w: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    scale = np.abs(w).max(axis=1) / 32767
    scale[scale == 0] = 1
    q = np.clip(np.round(w / scale[:, None]), -32767, 32767).astype("<i2")
    return q, scale


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("model")
    p.add_argument("out")
    p.add_argument("--hidden", type=int, default=512)
    p.add_argument("--games", type=int, default=300)
    args = p.parse_args()

    net = Net(args.hidden)
    net.load_state_dict(torch.load(args.model, map_location="cpu"))
    layers = [m for m in net.body if isinstance(m, nn.Linear)] + [net.pi]

    out_layers = []
    rounded = Net(args.hidden)
    rounded.load_state_dict(net.state_dict())
    rounded_layers = [m for m in rounded.body if isinstance(m, nn.Linear)] + [rounded.pi]
    for m, r in zip(layers, rounded_layers):
        w = m.weight.detach().double().numpy()
        q, scale = quantize(w)
        with torch.no_grad():
            r.weight.copy_(torch.from_numpy(q.astype(np.float64) * scale[:, None]))
        out_layers.append(
            {
                "q": base64.b64encode(q.tobytes()).decode(),
                "bits": 16,
                "scale": np.round(scale, 9).tolist(),
                "rows": int(w.shape[0]),
                "cols": int(w.shape[1]),
                "b": np.round(m.bias.detach().double().numpy(), 6).tolist(),
            }
        )
    json.dump(
        {
            "agent": "coop-selfplay",
            "activation": "relu",
            "obs": OBS_SIZE,
            "actions": N_ACTIONS,
            "layers": out_layers,
        },
        open(args.out, "w"),
        separators=(",", ":"),
    )
    print("wrote", args.out)
    print("original", evaluate(net, args.games))
    print("int16   ", evaluate(rounded, args.games))


if __name__ == "__main__":
    main()
