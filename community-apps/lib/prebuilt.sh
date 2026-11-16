# shellcheck shell=bash
# prebuilt.sh — shared by community-apps/*/install.sh.
#
# Reads an app's package lists from omaxian.deps.json and, when the app has a
# pinned pre-built binary, downloads and verifies it so the installer can skip
# compiling. Every check that fails prints why and returns 1; the caller then
# builds from source. See docs/omaxian/plans/community-apps-prebuilts.md.
#
# Manifest: <app>/.omaxian-prebuilt, one key=value per line:
#   url=     https release tarball
#   sha256=  checksum of the tarball, checked before extraction
#   tree=    Omaxian commit whose <app>/ the binary matches
#   bin=     path of the binary inside the tarball (default: the first
#            executable file named <name>)
#   arch=    machine the binary runs on (default: x86_64)
#   qt=      oldest Qt the binary runs on (Qt apps; e.g. 6.8)
#
# The caller sets ROOT (the app directory) and FROM_SOURCE (0/1), then:
#   source "$ROOT/../lib/prebuilt.sh"
#   app_deps_read                      # → apt_runtime[], apt_build[]
#   if prebuilt_fetch <name>; then …"$PREBUILT_BIN"… else …build… fi

PREBUILT_BIN=""
PREBUILT_TMP=""

# Files that only affect installing, never the compiled binary. Changes to
# them do not make a pinned binary stale.
PREBUILT_IGNORE=(
  ':(exclude).omaxian-prebuilt'
  ':(exclude)install.sh'
  ':(exclude)omaxian.deps.json'
  ':(exclude)*.md'
)

# Fill apt_runtime[] / apt_build[] from omaxian.deps.json (the same lists the
# TUI shows). jq is installed by scripts/setup.sh.
app_deps_read() {
  local deps="$ROOT/omaxian.deps.json"
  if ! command -v jq >/dev/null; then
    echo "jq not found — install it (sudo apt install jq); it reads $deps" >&2
    exit 1
  fi
  mapfile -t apt_runtime < <(jq -r '.apt // [] | .[]' "$deps")
  mapfile -t apt_build < <(jq -r '.apt_build // [] | .[]' "$deps")
}

# prebuilt_get <key> — value from the manifest (empty when unset).
prebuilt_get() {
  awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$ROOT/.omaxian-prebuilt"
}

# Installed libqt6core version, else apt's candidate (runtime apt has not run
# yet on a fresh system). Empty when neither exists.
prebuilt_qt_version() {
  local v
  v=$(dpkg-query -W -f '${Version}' libqt6core6t64 2>/dev/null || true)
  if [[ -z $v ]]; then
    v=$(apt-cache policy libqt6core6t64 2>/dev/null | awk '/Candidate:/ { print $2; exit }')
    [[ $v == "(none)" ]] && v=""
  fi
  printf '%s\n' "$v"
}

# True when <app>/ still matches the commit the binary was built from.
prebuilt_tree_current() {
  local tree="$1" changes
  command -v git >/dev/null || return 0
  git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  changes=$(git -C "$ROOT" status --porcelain -- . "${PREBUILT_IGNORE[@]}" 2>/dev/null || true)
  if [[ -n $changes ]]; then
    echo ">> local changes in $(basename "$ROOT")/ — building from source"
    return 1
  fi
  # A shallow clone (bootstrap.sh) may not have the commit; trust the pin.
  if [[ -z $tree ]] || ! git -C "$ROOT" cat-file -e "$tree^{commit}" 2>/dev/null; then
    return 0
  fi
  if ! git -C "$ROOT" diff --quiet "$tree" HEAD -- . "${PREBUILT_IGNORE[@]}" 2>/dev/null; then
    echo ">> $(basename "$ROOT")/ changed since the pre-built binary (${tree:0:12}) — building from source"
    return 1
  fi
  return 0
}

prebuilt_cleanup() {
  if [[ -n $PREBUILT_TMP ]]; then
    rm -rf -- "$PREBUILT_TMP"
    PREBUILT_TMP=""
  fi
}

# prebuilt_fetch <name> — download, verify and unpack the pinned binary.
# Sets PREBUILT_BIN on success. Returns 1 (with the reason) to fall back.
prebuilt_fetch() {
  local name="$1" manifest="$ROOT/.omaxian-prebuilt"
  local url sha tree bin arch qt have tarball got
  PREBUILT_BIN=""

  if (( ${FROM_SOURCE:-0} )); then
    echo ">> --from-source: building $name"
    return 1
  fi
  if [[ ! -f $manifest ]]; then
    echo ">> no pre-built $name yet — building from source"
    return 1
  fi
  url=$(prebuilt_get url)
  sha=$(prebuilt_get sha256)
  tree=$(prebuilt_get tree)
  bin=$(prebuilt_get bin)
  arch=$(prebuilt_get arch)
  qt=$(prebuilt_get qt)
  arch=${arch:-x86_64}

  if [[ $url != https://* || ! $sha =~ ^[0-9a-f]{64}$ ]]; then
    echo ">> $manifest needs an https url= and a sha256= — building from source" >&2
    return 1
  fi
  if [[ $bin == /* || $bin == *..* ]]; then
    echo ">> $manifest: bin= must be a relative path inside the tarball — building from source" >&2
    return 1
  fi
  if [[ $(uname -m) != "$arch" ]]; then
    echo ">> pre-built $name is $arch only — building from source"
    return 1
  fi
  if [[ -n $qt ]]; then
    have=$(prebuilt_qt_version)
    if [[ -z $have ]] || ! dpkg --compare-versions "$have" ge "$qt"; then
      echo ">> pre-built $name needs Qt ≥ $qt (found: ${have:-none}) — building from source"
      return 1
    fi
  fi
  prebuilt_tree_current "$tree" || return 1
  if ! command -v curl >/dev/null || ! command -v sha256sum >/dev/null; then
    echo ">> curl / sha256sum missing — building from source"
    return 1
  fi

  PREBUILT_TMP=$(mktemp -d "${TMPDIR:-/tmp}/omaxian-prebuilt.XXXXXX")
  trap prebuilt_cleanup EXIT
  tarball="$PREBUILT_TMP/app.tar.gz"
  echo ">> download pre-built $name"
  echo "   $url"
  if ! curl -fL --proto '=https' --tlsv1.2 --retry 2 --connect-timeout 20 -sS -o "$tarball" "$url"; then
    echo ">> download failed — building from source" >&2
    return 1
  fi
  got=$(sha256sum "$tarball" | awk '{ print $1 }')
  if [[ $got != "$sha" ]]; then
    echo ">> checksum mismatch for $name (expected $sha, got $got) — building from source" >&2
    return 1
  fi
  echo ">> sha256 ok"

  mkdir -p "$PREBUILT_TMP/x"
  if ! tar -xzf "$tarball" --no-same-owner -C "$PREBUILT_TMP/x"; then
    echo ">> could not unpack the tarball — building from source" >&2
    return 1
  fi
  if [[ -n $bin ]]; then
    bin="$PREBUILT_TMP/x/$bin"
  else
    bin=$(find "$PREBUILT_TMP/x" -type f -name "$name" -perm -u+x -print -quit)
  fi
  if [[ -z $bin || ! -f $bin || ! -x $bin || $(head -c 4 "$bin" | od -An -c | tr -d ' ') != '177ELF' ]]; then
    echo ">> tarball has no executable $name — building from source" >&2
    return 1
  fi
  PREBUILT_BIN=$bin
  return 0
}
