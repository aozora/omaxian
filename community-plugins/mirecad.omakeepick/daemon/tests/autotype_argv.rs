//! Auto-type never puts field values on xdotool's command line, which other users can read in
//! /proc/<pid>/cmdline. Runs the real `Xdotool` typist against a fake `xdotool` that records its
//! arguments and stdin.
//!
//! This is the only test in this binary because it changes PATH for the whole process.

use std::collections::HashMap;
use std::fs;
use std::os::unix::fs::PermissionsExt;

use omakeepickd::autotype::{self, Fields, Xdotool};
use zeroize::Zeroizing;

struct Entry(HashMap<&'static str, &'static str>);

impl Fields for Entry {
    fn field(&self, name: &str) -> Result<Option<Zeroizing<String>>, String> {
        Ok(self.0.get(name).map(|v| Zeroizing::new(v.to_string())))
    }
}

#[tokio::test]
async fn field_values_reach_xdotool_on_stdin_only() {
    let dir = tempfile::tempdir().unwrap();
    let log = dir.path();
    let fake = log.join("xdotool");
    fs::write(
        &fake,
        "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\" >> \"$(dirname \"$0\")/args\"; done\n\
         cat >> \"$(dirname \"$0\")/stdin\"\n",
    )
    .unwrap();
    fs::set_permissions(&fake, fs::Permissions::from_mode(0o755)).unwrap();
    let path = format!("{}:{}", log.display(), std::env::var("PATH").unwrap_or_default());
    // SAFETY: the only test in this binary, so no other thread reads the environment.
    unsafe { std::env::set_var("PATH", path) };

    let entry = Entry(HashMap::from([("PASSWORD", "S3cr3t!"), ("USERNAME", "joe"), ("TOTP", "123456")]));

    // A modifier before a field would type its first character as a chord; it is refused
    // before anything is typed.
    assert!(autotype::parse("{USERNAME}{TAB}+{PASSWORD}", &entry).is_err());

    let tokens = autotype::parse("^a{USERNAME}{TAB}{PASSWORD}{TAB}{TOTP}{ENTER}", &entry).unwrap();
    autotype::run(&tokens, &mut Xdotool, 0, || true).await.unwrap();

    // Only flags, key names, delays/repeats, and the chord's own literal `a`.
    let args = fs::read_to_string(log.join("args")).unwrap();
    for arg in args.lines() {
        let harmless = matches!(
            arg,
            "type"
                | "key"
                | "keydown"
                | "keyup"
                | "--delay"
                | "--repeat"
                | "--file"
                | "-"
                | "--"
                | "ctrl"
                | "a"
                | "Tab"
                | "Return"
                | "ctrl+Tab"
                | "shift+Insert"
        ) || arg.chars().all(|c| c.is_ascii_digit());
        assert!(harmless, "xdotool got {arg:?} as an argument");
    }
    assert_eq!(fs::read_to_string(log.join("stdin")).unwrap(), "ajoeS3cr3t!123456");
}
