# Committed baselines

Reference dumps of the QML layer as it behaves in this release. They exist so a
future change can be diffed against something instead of asserted about.

| File | Produced by | What it pins |
|---|---|---|
| `service-scenarios.txt` | `tests/qml-service-scenarios.sh` | The state the Service settles in for each mock scenario, the auth-during-refresh invariant, and the three index lifecycle cases |

Upstream also shipped nested-compositor panel snapshot / key-matrix / pixel
checks. Those need a Wayland session and are omitted from this Omaxian port;
`qml-service-scenarios.sh` remains (headless / offscreen).

Refresh `service-scenarios.txt` only when a change is *meant* to alter what it
records, and say so in the pull request that does it.
