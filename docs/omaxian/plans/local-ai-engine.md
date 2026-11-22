# Local AI engine without systemd (`omarchy-local-ai`)

Status: Phase 0 passed; Phase 1 (engine port) done and tested; Phase 2 (real
model) and Phase 3 (Flowtunes) not started.

Goal: run [omacom/omarchy-local-ai](https://github.com/omacom/omarchy-local-ai)
(pinned `e7fe801`, v0.9.0 packaging) and the `omarchy-agent-local` command on
Devuan, so Flowtunes (music) and later Fantasi can work. Both only drive
models through that engine, which today needs systemd user units.

Scope: the **music path** first (ACE-Step on `amd` / `intel` GPUs, rootless
Podman). Out of scope: DGX Spark pairing (`link-*`), the NVIDIA CDI path,
and the text-model recipes, until the music path works.

## What the engine is

`agent_local.py` (5.7k lines, Python 3.11+, stdlib only) resolves recipes,
downloads pinned Hugging Face files, checks memory and GPU admission, runs
each model as a rootless Podman container, and writes `status.json` /
`list.json` under `~/.local/state/omarchy/agent-local`, which apps watch.
Flowtunes calls only `refresh --quiet`, `start <id>`, `stop <id>` and
`use <id> --detach`.

## Where systemd is used

| Use | Where | Replacement |
| --- | --- | --- |
| Quadlet `.container` per model | `render_container` | Same typed fields rendered as `podman run` argv |
| Shared internal network | `render_network` | `podman network create --internal omarchy-agent-local` |
| start / stop / show / is-active / reset-failed | `systemctl()`, `unit_*` | Supervisor with a pidfile and state file per model |
| `Restart=on-failure`, 10 s, 3 starts per 10 min | `[Service]` | Supervisor loop with the same backoff |
| `HealthStartupCmd` / `HealthCmd`, `Notify=healthy` | `[Container]` | Supervisor runs the probe: every 2 s while loading, then every 30 s |
| `ExecStartPost` / `ExecStopPost` status hooks | `[Service]` | Supervisor writes `status.json` on each transition |
| `journalctl --user -u` | `journal_tail`, logs | Log file per model under the state dir |
| Transient `omarchy-agent-local-use-<recipe>` | `use --detach`, `update --detach` | Detached `setsid` process with a pidfile; `remove` kills its process group |
| `PartOf=graphical-session.target` | unit header | `omarchy-local-ai autostart`, run from the i3 session |
| linger, `systemd-run -M`, `DefaultLimitMEMLOCK`, NM dispatcher | pairing only | Dropped with pairing |

## Design

- Keep the change behind one backend seam (a `Supervisor` class), so merging
  upstream `agent_local.py` stays practical. Same port-sync method as the
  community apps: branch at the pinned commit, apply the port, merge the new
  tag.
- One detached watcher per running model: runs `podman run` in the
  foreground, probes health, applies the restart policy, writes status and
  logs. No long-lived system-wide daemon.
- `omarchy-hw-platform` (Omarchy helper the engine calls) gets a small shim.
- Wrappers `omarchy-agent-local` and `omarchy-models` in
  `omaxian/.local/share/omarchy/bin/` run the engine (the engine's own hooks
  and Flowtunes call them). Metadata per
  `agents/skills/command-metadata.md`.
- Lives in `community-apps/omarchy-local-ai/` with its own `install.sh` and
  `omaxian.deps.json` (python3, podman, crun, netavark, aardvark-dns, uidmap,
  slirp4netns or passt, rsync). Opt-in: models are multi-gigabyte.

## Phases

0. **Spike (throwaway).** Check rootless Podman on this Devuan host does what
   the engine needs. Gate for everything below.
1. **Engine port.** Supervisor backend, removals above, wrappers, installer,
   adapt `tests/engine-test.sh` (it asserts Quadlet output).
2. **Verify on this machine.** Setup of ACE-Step (7.57 GiB, needs the
   user's go-ahead), start, authenticated `/props`, kill the container and
   see it restart, stop, `remove` mid-setup, idle memory.
3. **Port Flowtunes.** Window class, deps, catalog row; update the "not
   ported" notes for Flowtunes and Fantasi.

## Risks

- The only AMD ACE-Step measurement is Strix Halo / 64 GB. This machine is a
  Krackan (Radeon 840M/860M, 62 GB). It should be offered the recipe, but
  speed and stability are unknown.
- Rootless Podman without systemd: cgroup delegation and health checks
  (Podman schedules them with systemd timers) may not work, hence the
  engine-side probe.
- Images come from Omacom's registry (digest-pinned, third-party review
  records ship with the catalog).

## Phase 0 checks

1. Packages present: podman, crun, netavark, aardvark-dns, uidmap, passt.
2. `podman network create --internal` works.
3. A container on that network can publish a port on `127.0.0.1` and has no
   outside route.
4. `--read-only`, `--cap-drop=all`, `--security-opt no-new-privileges`,
   `--tmpfs /tmp`, `--secret` (env type) work.
5. `--device /dev/dri/renderD128` with `--group-add keep-groups` works.
6. `--restart on-failure` restarts a killed container without systemd.
7. The ACE-Step image pulls and `ace-server` sees a Vulkan device.

## Phase 0 results

Run on this machine (Devuan, sysvinit as PID 1, Podman 5.4.2, cgroup v2 with
`cgroupfs`, netavark, pasta) on 2026-11-22. Nothing was installed.

| # | Check | Result |
| - | ----- | ------ |
| 1 | Packages | Already present: podman, crun, netavark, aardvark-dns, uidmap, passt, slirp4netns |
| 2 | `podman network create --internal` | Works |
| 3 | Published `127.0.0.1` port; no egress | Host reaches the port; `wget 1.1.1.1` from the container is blocked |
| 4 | `--read-only`, `--cap-drop=all`, `no-new-privileges`, `--tmpfs`, `--secret` env | All work (rootfs write refused, `CapEff` 0, secret visible as env) |
| 5 | `--device /dev/dri/renderD128 --group-add keep-groups` | Works. The node is world-writable (`root:video` 0666), so no `render` group is needed here |
| 6 | `--restart on-failure:3` without systemd | Works: a `kill -9` of the container's process was restarted (`RestartCount` 1). Podman handles this itself |
| 6b | `--health-cmd` without systemd | Does **not** run on its own (state stays `starting`, no log entries). `podman healthcheck run <name>` works by hand. The supervisor therefore runs the probe itself, as planned |
| 7 | ACE-Step image | Pulled (380 MiB, 6 layers). `ace-server` starts under the hardened flags and `ggml_vulkan` finds `AMD Radeon 860M Graphics (RADV KRACKAN1)`, `uma: 1`, `KHR_coopmat` |

Notes for Phase 1:

- Podman restarts crashed containers by itself, so the supervisor mostly needs
  the health probe, status writes and the start limit (3 per 10 min).
- Real model files were not loaded; whether ACE-Step renders a song on
  Krackan, and how fast, is a Phase 2 question.
- Do not read from `/dev/dri/renderD128` in tests: it blocks.
- The pulled ACE-Step image stays in the user's Podman store (about 380 MiB).


## Phase 1 results

Ported into `community-apps/omarchy-local-ai/` (pin `e7fe801`).

- `omaxian_units.py` (new): the unit layer. `systemctl()` emulation for
  `show`, `start`, `stop`, `reset-failed`, `is-active` and `daemon-reload`, a
  supervisor per model (run, probe, restart, hooks, state), detached runs
  (`run_transient`, `_exec`) and log files. A process is "the unit" while it
  holds an flock, so a crashed one never looks active.
- `agent_local.py`: `render_container` writes a JSON spec of `podman run`
  flags; `write_unit_files` makes the internal network; `start_unit`,
  `detach_use`, `detach_update`, `cmd_logs` and `journal_tail` use the new
  layer; the share proxy raises; `share`, `network`, `pair`, `forget`, `link`,
  `link-worker` and `share-proxy` are removed from the command table; two hidden
  commands `supervise` and `_exec` are added. Pairing code is left in place
  (dead) so upstream merges stay small. No autostart: upstream's units had no
  `[Install]` either.
- `omarchy-agent-local`, `omarchy-models`, `omarchy-local-ai` are symlinks to
  the engine entry, installed by `install.sh` into `~/.local/bin`.
- Tests: `tests/engine-test.sh` passes (352 checks; the 7 pair-unit checks are
  listed in `tests/omaxian-expected-failures.txt`); `tests/omaxian-test.sh`
  (new, 19 checks) runs the supervisor against real Podman: start waits for
  health, crash then automatic restart, hooks, stop, stop mid-load, start
  limit, transient runs.
- On this machine `omarchy-local-ai list` reports `amd-gfx1152, 64 GB` and
  offers ACE-Step (and the image models).

Known gaps:

- `ControlGroup` (for `memory` and the panel's memory bar) is read from the
  container's `/proc/<pid>/cgroup`; on this rootless cgroupfs setup it was `/1`.
  Whether that gives real numbers is untested.
- Nothing starts a model at login.
- Not run against a real model yet (Phase 2).
