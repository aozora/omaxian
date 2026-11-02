//! Clipboard access through `xclip` (preferred) or `xsel`.
//!
//! X11 has no clipboard "sensitive" flag, so a clipboard manager may see the
//! value. Copied secrets are still cleared after a timeout, but only if the
//! clipboard still holds them.

use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Mutex;
use std::time::Duration;

use sha2::{Digest, Sha256};
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

#[derive(Clone, Copy)]
enum Tool {
    Xclip,
    Xsel,
}

fn on_path(name: &str) -> bool {
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    std::env::split_paths(&path).any(|dir| {
        let candidate: PathBuf = dir.join(name);
        candidate.is_file()
    })
}

fn resolve_tool() -> Result<Tool, String> {
    if on_path("xclip") {
        Ok(Tool::Xclip)
    } else if on_path("xsel") {
        Ok(Tool::Xsel)
    } else {
        Err("tool_missing:xclip (or xsel) is not installed".into())
    }
}

async fn write_selection(tool: Tool, primary: bool, data: Option<&[u8]>) -> Result<(), String> {
    let mut child = match tool {
        Tool::Xclip => {
            let selection = if primary { "primary" } else { "clipboard" };
            Command::new("xclip")
                .args(["-selection", selection, "-t", "text/plain"])
                .stdin(if data.is_some() { Stdio::piped() } else { Stdio::null() })
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
        }
        Tool::Xsel => {
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
                .spawn()
        }
    }
    .map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => "tool_missing:xclip (or xsel) is not installed".to_string(),
        _ => format!("Cannot run clipboard tool: {e}"),
    })?;

    if let Some(data) = data {
        let mut stdin = child.stdin.take().expect("piped stdin");
        stdin.write_all(data).await.map_err(|e| format!("clipboard write: {e}"))?;
    }
    let status = child.wait().await.map_err(|e| format!("clipboard: {e}"))?;
    if !status.success() {
        return Err("clipboard tool failed".into());
    }
    Ok(())
}

/// Puts `data` on the clipboard (or the primary selection) as text.
pub async fn set(data: &[u8], primary: bool) -> Result<(), String> {
    let tool = resolve_tool()?;
    write_selection(tool, primary, Some(data)).await
}

async fn clear(primary: bool) {
    let Ok(tool) = resolve_tool() else { return };
    match tool {
        Tool::Xclip => {
            // Empty write clears the selection (xclip has no --clear).
            let _ = write_selection(tool, primary, Some(b"")).await;
        }
        Tool::Xsel => {
            let _ = write_selection(tool, primary, None).await;
        }
    }
}

pub async fn clear_all() {
    clear(false).await;
    clear(true).await;
}

async fn read() -> Option<Vec<u8>> {
    let tool = resolve_tool().ok()?;
    let out = match tool {
        Tool::Xclip => {
            Command::new("xclip")
                .args(["-selection", "clipboard", "-o"])
                .stdin(Stdio::null())
                .stderr(Stdio::null())
                .output()
                .await
                .ok()?
        }
        Tool::Xsel => {
            Command::new("xsel")
                .args(["--clipboard", "--output"])
                .stdin(Stdio::null())
                .stderr(Stdio::null())
                .output()
                .await
                .ok()?
        }
    };
    out.status.success().then_some(out.stdout)
}

fn digest(data: &[u8]) -> [u8; 32] {
    Sha256::digest(data).into()
}

/// Tracks the secret we last copied (as a hash) so it can be cleared later without clobbering
/// anything the user copied in the meantime.
#[derive(Default)]
pub struct Clipboard {
    current: Mutex<Option<(u64, [u8; 32])>>,
}

impl Clipboard {
    /// Copies `value` and returns a ticket for [`clear_if_unchanged`](Self::clear_if_unchanged).
    pub async fn copy(&self, value: &[u8]) -> Result<u64, String> {
        set(value, false).await?;
        let mut current = self.current.lock().expect("clipboard lock");
        let ticket = current.map_or(1, |(t, _)| t + 1);
        *current = Some((ticket, digest(value)));
        Ok(ticket)
    }

    /// Clears the clipboard after `delay` if it still holds the value copied under `ticket`.
    pub async fn clear_if_unchanged(&self, ticket: u64, delay: Duration) {
        tokio::time::sleep(delay).await;
        let expected = match *self.current.lock().expect("clipboard lock") {
            Some((t, hash)) if t == ticket => hash,
            _ => return,
        };
        self.clear_matching(expected).await;
    }

    /// Clears the clipboard right away if it still holds our last secret (used on lock).
    pub async fn clear_now(&self) {
        let expected = match *self.current.lock().expect("clipboard lock") {
            Some((_, hash)) => hash,
            None => return,
        };
        self.clear_matching(expected).await;
    }

    async fn clear_matching(&self, expected: [u8; 32]) {
        let held = read().await.map(|mut data| {
            let hash = digest(&data);
            zeroize::Zeroize::zeroize(&mut data);
            hash
        });
        if held == Some(expected) {
            clear(false).await;
        }
        let mut current = self.current.lock().expect("clipboard lock");
        if current.is_some_and(|(_, hash)| hash == expected) {
            *current = None;
        }
    }
}
