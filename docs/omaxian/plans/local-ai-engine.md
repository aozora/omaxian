# Local AI engine without systemd (`omarchy-local-ai`)

Status: Phase 0 passed; Phase 1 (engine port) done and tested; Phase 2 (real
model) done except music generation; Phase 3 (Flowtunes) ported, installed and verified with a real render.

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

## Phase 2 results

Run on this machine on 2026-11-22 with `ace-step-1.5-turbo-acestep`.

- Setup downloaded 7.6 GiB (about 34 MiB/s), then the first start failed:
  `quadlet_path` pointed at `<unit>.container` while the supervisor reads
  `<unit>.service.spec.json`. Fixed (`quadlet_path` now returns `spec_path`).
  The unit tests missed it because they wrote the spec by hand.
- Start: healthy in 2.5 s, `observed` 8 GiB RAM. `/props` is 401 without the
  key and 200 with it (acestep.cpp 973517b, LM + DiT + VAE + embedding listed).
- Crash: `kill -9` of the container's process was restarted by the supervisor
  in about 12 s (`auto-restart`, then active); `/props` 200 again.
- `stop`: clean, state `inactive`, container gone.
- Not done: a real song render (speed on Krackan unknown), and `remove`
  mid-setup against the real download.
- Confirmed gap: `podman stats` / the container's `ControlGroup` is `/1`, so
  cgroup memory files are not found. `observed.ram_used_gib` (from free memory)
  works; per-model live memory does not.

## Phase 3 results

`community-apps/flowtunes/` (upstream `8a9a76f`, 0.2.0). Two QML fixes were
needed for Qt 6.8: `long` / `short` are reserved words there, and
`styleHints.accessibility` is Qt 6.10+. Built and tested in a Debian trixie
container (Qt 6.8.2): all upstream tests pass, qmllint is clean. The host
has no ShaderTools for its Qt 6.10 overlay (and Qt Test is incomplete there), so
`install.sh` builds in a trixie container when needed and installs a wrapper for
QtMultimedia under `~/.local/lib`. Run on the desktop against the real model:
`flowtunes jazz` made a 2:59 instrumental ("Midnight Rain") in about 2m15s on
the Krackan GPU, so it renders faster than it plays; it was saved to
`~/Music/Jazz/` and played. The engine is installed in `~/.local` for this.
Flowtunes, Fantasi, and the engine are in `CI_APPS` as of v1.2.4 (the engine
is packaged as a script tree, not compiled). No audible check (the run was
headless).

## Fantasi

`community-apps/fantasi/` (upstream `c7e0869`, 0.1.7 plus six commits), ported
the same way as Flowtunes. Patches: the same two Qt 6.8 QML fixes and the
optional Qt Test; `omarchy-launch-or-focus` became `i3-msg … focus`; the
`omarchy models …` hints became `omarchy-models …`; and one real Qt 6.8 bug
(`contentItem.forceActiveFocus()` leaves the focus in the prompt's scope, so F,
Delete and the arrows did nothing: `releasePrompt()`). Tested on Qt 6.8 as a
normal user (a test makes a folder read-only, so root fails it): all pass;
qmllint clean. On the desktop, `fantasi generate --music … --instrumental
--seconds 30` made a 29 s MP3 in 35 s, and the window renders. Image and video
models (sdcpp) have not been run; untested.
