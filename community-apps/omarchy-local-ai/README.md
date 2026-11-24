# omarchy-local-ai (Omaxian port)

The local-model engine and recipe catalog behind Omarchy's `omarchy-agent-local`.
It downloads pinned open models and runs each in a rootless Podman container on
your GPU, with a key-protected loopback endpoint. Apps such as Flowtunes (music)
and Fantasi drive it through `omarchy-agent-local`.

Port of [omacom/omarchy-local-ai](https://github.com/omacom/omarchy-local-ai)
(upstream commit `63b3be9`, v0.13.0 packaging, pinned in
`.omaxian-upstream-commit`). Upstream docs: [`README.upstream.md`](README.upstream.md)
and [`docs/engine.md`](docs/engine.md).

This is a **standalone app** (Python, no build step), not a Quickshell plugin. It
lives under `community-apps/` so `./scripts/deploy.sh` never copies it into `$HOME`.

## Omaxian deltas

| Upstream (Omarchy) | This port |
| ------------------ | --------- |
| Each model is a systemd user unit written as a Podman Quadlet | Each model is a **supervisor process** (`omaxian_units.py`, started as `omarchy-local-ai supervise <unit>`): it runs `podman run` in the foreground, probes the model's health (every 2 s while loading, then 30 s; three failures kill it), restarts it on failure (10 s apart, at most 3 starts in 10 min) and rewrites `status.json` on each change. `render_container` writes the unit as a JSON spec of `podman run` flags instead of Quadlet text |
| `systemctl --user` / `journalctl --user` | `systemctl()` in `agent_local.py` answers from the supervisor's state files (`~/.local/state/omarchy/agent-local/units/`); logs are plain files in `.../logs/`, shown by `omarchy-agent-local logs <recipe>` |
| A detached setup is a transient unit from `systemd-run` | A detached process in its own session that holds a lock file, so `remove` can cancel it |
| `[Install]` / graphical-session | Models do **not** start at login (upstream does not either). Start one with `omarchy-agent-local start <recipe>` |
| Quadlet `.network` | `podman network create --internal omarchy-agent-local`, made on first use |
| Podman health checks | Podman only schedules them with systemd timers, so the supervisor runs the probe itself |
| Spark pairing (`link`, `pair`, `forget`), tailnet sharing (`share`, `network`, `share-proxy`) | Removed. Paired runtimes are refused. The code is left in `agent_local.py` to keep upstream merges small |
| Arch package `omarchy-local-ai`; `omarchy models` dispatcher | `install.sh` copies the tree to `~/.local/share/omarchy-local-ai` and links `omarchy-local-ai`, `omarchy-agent-local` and `omarchy-models` in `~/.local/bin` |
| `tests/engine-test.sh` | Same file, which now keeps going after a failed check and compares the failures with `tests/omaxian-expected-failures.txt` (the pair unit). Checks for Quadlet output, tailnet sharing and `systemd-run` were changed or removed. `tests/omaxian-test.sh` covers the supervisor against real Podman |

## Requirements

Runtime (also in `omaxian.deps.json`): `python3` (3.11+), `podman`, `crun`,
`netavark`, `aardvark-dns`, `uidmap`, `passt`, `mesa-vulkan-drivers`. Your user needs
subordinate ids (a line in `/etc/subuid` and `/etc/subgid`).

GPU: AMD or Intel through Vulkan (`/dev/dri/renderD*`). The NVIDIA recipes need
NVIDIA's container toolkit (CDI) and have not been tried here.

## Install

```bash
community-apps/omarchy-local-ai/install.sh        # or --skip-apt
```

Nothing is downloaded until you set a model up.

## Use

```bash
omarchy-agent-local list                           # recipes, and which fit this machine
omarchy-agent-local use ace-step-1.5-turbo-acestep # set up and start (7.6 GiB weights + a 380 MiB image)
omarchy-agent-local status
omarchy-agent-local logs ace-step-1.5-turbo-acestep
omarchy-agent-local stop
omarchy-agent-local remove ace-step-1.5-turbo-acestep
```

State: `~/.local/state/omarchy/agent-local` (status, units, logs) and
`~/.local/share/omarchy/agent-local` (weights). The key is
`~/.config/omarchy/agent-local/key`.

## Check it

- `community-apps/omarchy-local-ai/tests/engine-test.sh` (catalog, admission, downloads).
- `community-apps/omarchy-local-ai/tests/omaxian-test.sh` (supervisor; uses Podman and an alpine image already in its store, never pulls).
- `omarchy-local-ai validate community-apps/omarchy-local-ai`.

## Uninstall

```bash
omarchy-agent-local stop
rm -f ~/.local/bin/omarchy-local-ai ~/.local/bin/omarchy-agent-local ~/.local/bin/omarchy-models
rm -rf ~/.local/share/omarchy-local-ai
# Models and state, if you want them gone too (weights are large):
rm -rf ~/.local/share/omarchy/agent-local ~/.local/state/omarchy/agent-local ~/.config/omarchy/agent-local
```

## License

MIT (upstream).
