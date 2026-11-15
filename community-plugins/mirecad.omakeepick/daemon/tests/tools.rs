//! What becomes of the programs the daemon hands a secret to, against the stand-ins for `wtype`
//! and `wl-copy` in `tests/fixtures/bin`.
//!
//! This is the only test in this binary because it changes the environment of the whole
//! process.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use omakeepickd::autotype::{Typist, Xdotool};
use omakeepickd::clipboard::Clipboard;
use omakeepickd::inflight::Tracker;
use zeroize::Zeroizing;

struct Fake(PathBuf);

impl Fake {
    fn read(&self, name: &str) -> String {
        fs::read_to_string(self.0.join(name)).unwrap_or_default()
    }

    fn reset(&self) {
        for entry in fs::read_dir(&self.0).unwrap().flatten() {
            fs::remove_file(entry.path()).unwrap();
        }
    }

    fn selection(&self, which: &str) -> Option<String> {
        let path = self.0.join(which);
        path.is_file().then(|| self.read(which)).filter(|s| !s.is_empty())
    }
}

fn set(name: &str, value: &str) {
    // SAFETY: the only test in this binary, so no other thread reads the environment.
    unsafe { std::env::set_var(name, value) };
}

fn unset(name: &str) {
    // SAFETY: as above.
    unsafe { std::env::remove_var(name) };
}

/// Waits until `check` holds. What a stand-in records, it records a moment after the daemon's
/// side of the exchange is done.
async fn eventually(what: &str, check: impl Fn() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !check() {
        assert!(Instant::now() < deadline, "timed out waiting until {what}");
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
}

/// Waits until only `left` holders are left: the owners that are meant to be there.
async fn settled_but_for(inflight: &Tracker, left: usize) {
    eventually("the tools that were dropped are gone", || inflight.count() <= left).await;
    assert_eq!(inflight.count(), left);
}

/// Everything a tool was started for is over once the tracker is back at zero: it was waited
/// for, and its scratch directory removed.
async fn settled(inflight: &Tracker) {
    tokio::time::timeout(Duration::from_secs(5), inflight.settled()).await.expect("a tool is still running");
}

#[tokio::test]
async fn tools_end_with_what_started_them() {
    let dir = tempfile::tempdir().unwrap();
    let fake = Fake(dir.path().join("fake"));
    let runtime = dir.path().join("run");
    fs::create_dir(&fake.0).unwrap();
    let bin = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/bin");
    set("PATH", &format!("{}:{}", bin.display(), std::env::var("PATH").unwrap_or_default()));
    set("FAKE_DIR", fake.0.to_str().unwrap());
    set("OMAKEEPICK_RUNTIME_DIR", runtime.to_str().unwrap());
    let inflight = Tracker::default();

    // Typing: all of the text arrives. wtype takes no delay of 0, so none is passed then.
    let mut xdotool = Xdotool::new(&inflight);
    xdotool.text("čšž-ľťň p@ss", 0).await.unwrap();
    xdotool.text("!", 8).await.unwrap();
    assert_eq!(fake.read("typed"), "čšž-ľťň p@ss!");
    assert!(fake.read("xdotool.log").contains("type"));
    assert_eq!(inflight.count(), 0);

    fake.reset();
    set("FAKE_KEY_SECONDS", "0.05");
    assert!(tokio::time::timeout(Duration::from_millis(80), xdotool.text("0123", 0)).await.is_err());
    assert_eq!(inflight.count(), 1, "the xdotool it left behind is not accounted for");
    settled(&inflight).await;
    assert_eq!(fake.read("typed"), "0123");
    unset("FAKE_KEY_SECONDS");

  let clipboard = Clipboard::new(inflight.clone());
  fake.reset();
  let owner = clipboard.offer("s3cret", false).await.unwrap();
  eventually("clipboard has the value", || fake.selection("clipboard").as_deref() == Some("s3cret")).await;
  drop(owner);
  settled(&inflight).await;
  eventually("clipboard was cleared", || fake.selection("clipboard").is_none()).await;

  fake.reset();
  let owner = clipboard.offer("s3cret", true).await.unwrap();
  eventually("primary has the value", || fake.selection("primary").as_deref() == Some("s3cret")).await;
  drop(owner);
  settled(&inflight).await;

  set("FAKE_XCLIP", "fails");
  assert_eq!(clipboard.offer("s3cret", false).await.err().as_deref(), Some("clipboard tool failed"));
  unset("FAKE_XCLIP");

  fake.reset();
  let copy = |value: &str| clipboard.copy(Zeroizing::new(value.into()));
  copy("first").await.unwrap();
  eventually("clipboard has the value", || fake.selection("clipboard").as_deref() == Some("first")).await;
  clipboard.forget();
  settled(&inflight).await;
  eventually("clipboard was cleared", || fake.selection("clipboard").is_none()).await;

  let first = copy("first").await.unwrap();
  let second = copy("second").await.unwrap();
  clipboard.clear_if_unchanged(first, Duration::from_millis(10)).await;
  eventually("second copy is on the clipboard", || fake.selection("clipboard").as_deref() == Some("second")).await;
  clipboard.clear_if_unchanged(second, Duration::from_millis(10)).await;
  settled(&inflight).await;
  eventually("clipboard was cleared", || fake.selection("clipboard").is_none()).await;

  fake.reset();
  copy("ours").await.unwrap();
  fs::write(fake.0.join("clipboard"), "theirs").unwrap();
  clipboard.forget();
  settled(&inflight).await;
  assert_eq!(fake.selection("clipboard").as_deref(), Some("theirs"));

  fake.reset();
  set("FAKE_XCLIP", "taken-over");
  copy("kept by a manager").await.unwrap();
  eventually("manager kept a copy", || fake.read("clipboard.kept") == "kept by a manager").await;
  clipboard.forget();
  settled(&inflight).await;
  assert!(fake.read("xclip.log").contains("clear clipboard"));
  unset("FAKE_XCLIP");
}
