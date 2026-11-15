//! Clipboard access through `xclip` (preferred) or `xsel`.
//!
//! X11 has no clipboard "sensitive" flag, so a clipboard manager may see the
//! value. Copied secrets are still cleared after a timeout, but only if the
//! clipboard still holds them (compared by a salted hash, not by keeping a
//! long-lived helper process as on Wayland).
//!
//! Values written for a paste are held by an [`Owner`] until it is dropped; then
//! the selection is read once and cleared if it still matches.

use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use sha2::{Digest, Sha256};
use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tokio::runtime::Handle;
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use crate::inflight::Tracker;

#[derive(Clone, Copy)]
enum ClipTool {
    Xclip,
    Xsel,
}

/// For a tool that is only asked something: reading the selection and clearing it.
const LOOKUP_TIMEOUT: Duration = Duration::from_secs(2);

fn on_path(name: &str) -> bool {
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    std::env::split_paths(&path).any(|dir| {
        let candidate: PathBuf = dir.join(name);
        candidate.is_file()
    })
}

fn cannot_run(e: std::io::Error) -> String {
    match e.kind() {
        std::io::ErrorKind::NotFound => "tool_missing:xclip (or xsel) is not installed".to_string(),
        _ => format!("Cannot run clipboard tool: {e}"),
    }
}

fn resolve_tool() -> Result<ClipTool, String> {
    if on_path("xclip") {
        Ok(ClipTool::Xclip)
    } else if on_path("xsel") {
        Ok(ClipTool::Xsel)
    } else {
        Err("tool_missing:xclip (or xsel) is not installed".into())
    }
}

async fn write_selection(tool: ClipTool, primary: bool, data: Option<&[u8]>) -> Result<(), String> {
    let mut child = match tool {
        ClipTool::Xclip => {
            let selection = if primary { "primary" } else { "clipboard" };
            Command::new("xclip")
                .args(["-selection", selection, "-t", "text/plain"])
                .stdin(if data.is_some() { Stdio::piped() } else { Stdio::null() })
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .kill_on_drop(true)
                .spawn()
        }
        ClipTool::Xsel => {
            let selection = if primary { "--primary" } else { "--clipboard" };
            let mut cmd = Command::new("xsel");
            cmd.arg(selection);
            if data.is_some() {
                cmd.arg("--input");
            } else {
                cmd.arg("--clear");
            }
            cmd.stdin(if data.is_some() { Stdio::piped() } else { Stdio::null() })
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .kill_on_drop(true)
                .spawn()
        }
    }
    .map_err(cannot_run)?;

    if let Some(data) = data {
        use tokio::io::AsyncWriteExt;
        let mut stdin = child.stdin.take().expect("piped stdin");
        stdin.write_all(data).await.map_err(|e| format!("clipboard write: {e}"))?;
    }
    let status = child.wait().await.map_err(|e| format!("clipboard: {e}"))?;
    if !status.success() {
        return Err("clipboard tool failed".into());
    }
    Ok(())
}

async fn clear(primary: bool) {
    let Ok(tool) = resolve_tool() else { return };
    match tool {
        ClipTool::Xclip => {
            let _ = write_selection(tool, primary, Some(b"")).await;
        }
        ClipTool::Xsel => {
            let _ = write_selection(tool, primary, None).await;
        }
    }
}

/// What it takes to know a value again without keeping it: a salted hash and the length. On
/// the heap, so that moving its owner about leaves no copy of it behind, and wiped when dropped.
#[derive(Zeroize, ZeroizeOnDrop)]
struct Mark {
    salt: [u8; 16],
    hash: [u8; 32],
    len: usize,
}

impl Mark {
    fn hash(salt: &[u8; 16], data: &[u8]) -> [u8; 32] {
        Sha256::new().chain_update(salt).chain_update(data).finalize().into()
    }

    fn of(data: &[u8]) -> Box<Mark> {
        let mut mark = Box::new(Mark { salt: [0; 16], hash: [0; 32], len: data.len() });
        let _ = getrandom::fill(&mut mark.salt);
        mark.hash = Mark::hash(&mark.salt, data);
        mark
    }

    fn is(&self, data: &[u8]) -> bool {
        let mut hash = Mark::hash(&self.salt, data);
        let same = data.len() == self.len && hash == self.hash;
        hash.zeroize();
        same
    }
}

/// Holds a value on a selection until dropped; then it is cleared if still ours.
pub struct Owner {
    primary: bool,
    /// Taken by `drop`.
    mark: Option<Box<Mark>>,
    inflight: Tracker,
}

impl Owner {
    /// For an owner whose selection another one of ours has just taken.
    fn superseded(mut self) {
        self.mark = None;
    }
}

impl Drop for Owner {
    fn drop(&mut self) {
        let (Some(mark), Ok(runtime)) = (self.mark.take(), Handle::try_current()) else { return };
        let primary = self.primary;
        let guard = self.inflight.hold();
        let hurried = guard.hurried();
        runtime.spawn(async move {
            let look = async {
                if read(primary, mark.len).await.is_some_and(|seen| mark.is(&seen)) {
                    clear(primary).await;
                }
            };
            tokio::select! {
                () = look => {}
                () = hurried => {}
            }
            drop(guard);
        });
    }
}

/// The value copied last, for as long as it is ours to take back.
struct Held {
    ticket: u64,
    owner: Owner,
}

pub struct Clipboard {
    inflight: Tracker,
    next: AtomicU64,
    turn: tokio::sync::Mutex<()>,
    current: Mutex<Option<Held>>,
}

impl Clipboard {
    pub fn new(inflight: Tracker) -> Clipboard {
        Clipboard {
            inflight,
            next: AtomicU64::new(1),
            turn: tokio::sync::Mutex::new(()),
            current: Mutex::new(None),
        }
    }

    /// Puts `data` on the clipboard (or the primary selection) as text, for as long as the
    /// returned owner exists.
    pub async fn offer(&self, data: impl AsRef<[u8]>, primary: bool) -> Result<Owner, String> {
        let data = data.as_ref();
        let tool = resolve_tool()?;
        let mark = Mark::of(data);
        write_selection(tool, primary, Some(data)).await?;
        Ok(Owner { primary, mark: Some(mark), inflight: self.inflight.clone() })
    }

    /// Copies `value` and returns a ticket for [`clear_if_unchanged`](Self::clear_if_unchanged).
    pub async fn copy(&self, value: Zeroizing<String>) -> Result<u64, String> {
        let _turn = self.turn.lock().await;
        let owner = self.offer(value.as_bytes(), false).await?;
        let ticket = self.next.fetch_add(1, Ordering::Relaxed);
        let previous = self.current.lock().expect("clipboard lock").replace(Held { ticket, owner });
        if let Some(previous) = previous {
            previous.owner.superseded();
        }
        Ok(ticket)
    }

    /// Takes the value copied under `ticket` back after `delay`, unless something else was
    /// copied since.
    pub async fn clear_if_unchanged(&self, ticket: u64, delay: Duration) {
        tokio::time::sleep(delay).await;
        let held = {
            let mut current = self.current.lock().expect("clipboard lock");
            if current.as_ref().is_some_and(|held| held.ticket == ticket) { current.take() } else { None }
        };
        drop(held);
    }

    /// Takes the value copied last back, right now: this is what a lock calls.
    pub fn forget(&self) {
        let held = self.current.lock().expect("clipboard lock").take();
        drop(held);
    }
}

/// The text on a selection, if it is no longer than `limit` bytes.
async fn read(primary: bool, limit: usize) -> Option<Zeroizing<Vec<u8>>> {
    let tool = resolve_tool().ok()?;
    let look = async {
        let mut child = match tool {
            ClipTool::Xclip => {
                let selection = if primary { "primary" } else { "clipboard" };
                Command::new("xclip")
                    .args(["-selection", selection, "-o"])
                    .stdin(Stdio::null())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::null())
                    .kill_on_drop(true)
                    .spawn()
                    .ok()?
            }
            ClipTool::Xsel => {
                let selection = if primary { "--primary" } else { "--clipboard" };
                Command::new("xsel")
                    .args([selection, "--output"])
                    .stdin(Stdio::null())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::null())
                    .kill_on_drop(true)
                    .spawn()
                    .ok()?
            }
        };
        let mut out = child.stdout.take()?;
        let mut seen = Zeroizing::new(vec![0u8; limit + 1]);
        let mut filled = 0;
        while filled < seen.len() {
            match out.read(&mut seen[filled..]).await {
                Ok(0) => break,
                Ok(n) => filled += n,
                Err(_) => return None,
            }
        }
        if filled > limit || !child.wait().await.ok()?.success() {
            return None;
        }
        seen.truncate(filled);
        Some(seen)
    };
    tokio::time::timeout(LOOKUP_TIMEOUT, look).await.ok().flatten()
}