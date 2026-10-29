"""Export the trained policy network to JSON for lib/sim/rl_strategy.dart.

    uv run python export.py [models/hint_policy.zip] [../assets/models/hint_policy.json]

Only the actor is needed to pick hints: the policy MLP (tanh layers) followed
by the action head. Also checks the JSON reproduces PyTorch's logits.
"""

import json
import sys
from pathlib import Path

import numpy as np
import torch
from sb3_contrib import MaskablePPO

from hanabi.env import HintEnv


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else "models/hint_policy.zip"
    dst = Path(sys.argv[2] if len(sys.argv) > 2 else "../assets/models/hint_policy.json")
    policy = MaskablePPO.load(src, device="cpu").policy
    meta = Path(src).with_suffix(".json")
    features = json.loads(meta.read_text())["features"] if meta.exists() else "v1"

    linears = [m for m in policy.mlp_extractor.policy_net if isinstance(m, torch.nn.Linear)]
    linears.append(policy.action_net)
    assert all(
        isinstance(m, torch.nn.Tanh)
        for m in policy.mlp_extractor.policy_net
        if not isinstance(m, torch.nn.Linear)
    )
    layers = [
        {"w": m.weight.detach().numpy().tolist(), "b": m.bias.detach().numpy().tolist()}
        for m in linears
    ]

    # Sanity check: a plain numpy forward pass must match PyTorch.
    env = HintEnv(features)
    obs, _ = env.reset(seed=1)
    x = obs
    for i, layer in enumerate(layers):
        x = np.asarray(layer["w"]) @ x + np.asarray(layer["b"])
        if i < len(layers) - 1:
            x = np.tanh(x)
    with torch.no_grad():
        ref = policy.action_net(policy.mlp_extractor.forward_actor(torch.as_tensor(obs[None]))).numpy()[0]
    assert np.allclose(x, ref, atol=1e-4), (x, ref)

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(json.dumps({"features": features, "layers": layers}))
    sizes = " -> ".join(str(len(l["b"])) for l in layers)
    print(f"Wrote {dst} ({features}: {len(obs)} -> {sizes}, {dst.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
