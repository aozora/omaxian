//! Omaxian: what the recorder asks Hyprland, answered on X11 and i3 instead.
//!
//! Upstream reads monitors, keyboards and the pointer from Hyprland (`hyprctl` and its IPC
//! socket). Without a Hyprland instance ([`hyprland`] is false) the call sites ask this module:
//!
//! - monitors: `xrandr --listactivemonitors`, the focused one and the space bars reserve from
//!   `i3-msg -t get_workspaces`, printed as `hyprctl -j monitors` would print them
//!   ([`monitors_json`]), so upstream's parsers read them unchanged;
//! - keyboards: `setxkbmap -query` ([`keyboards`]);
//! - the pointer: `XQueryPointer` on a display connection of the caller's own ([`Pointer`]).
//!
//! X11 coordinates are pixels with no scale, which is what Hyprland's logical coordinates are at
//! scale 1.

use crate::keymap::{KeyboardNames, Keyboards};
use omareel_core::compat::geometry::PointF;
use omareel_core::compat::qjson::{self, Format, Object, Value};
use omareel_core::compat::qprocess;
use std::ffi::{c_char, c_int, c_uint, c_ulong, c_void};

/// Whether a Hyprland instance runs this session: `$HYPRLAND_INSTANCE_SIGNATURE` is set.
pub fn hyprland() -> bool {
    std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some_and(|value| !value.is_empty())
}

/// What `program` printed when it succeeded within a second.
fn output(program: &str, arguments: &[&str]) -> Option<Vec<u8>> {
    qprocess::run(program, arguments, 1000).filter(qprocess::Finished::succeeded).map(|finished| finished.stdout)
}

/// One monitor of `xrandr --listactivemonitors`.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Monitor {
    pub name: String,
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub primary: bool,
}

/// `W/mmxH/mm+X+Y` (the millimetres are optional).
fn parse_geometry(text: &str) -> Option<(i32, i32, i32, i32)> {
    let (size, position) = text.split_once('+')?;
    let (x, y) = position.split_once('+')?;
    let (width, height) = size.split_once('x')?;
    let number = |part: &str| part.split('/').next()?.parse::<i32>().ok();
    Some((number(width)?, number(height)?, x.parse().ok()?, y.parse().ok()?))
}

/// The monitors in what `xrandr --listactivemonitors` printed:
///
/// ```text
/// Monitors: 2
///  0: +*DP-1 2560/597x1440/336+0+0  DP-1
///  1: +HDMI-1 1920/527x1080/296+2560+0  HDMI-1
/// ```
///
/// The name is the last field (the output, which gpu-screen-recorder captures by); `*` marks the
/// primary one.
pub fn parse_active_monitors(text: &str) -> Vec<Monitor> {
    let mut result = Vec::new();
    for line in text.lines().skip_while(|line| !line.trim_start().starts_with("Monitors:")).skip(1) {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 4 {
            continue;
        }
        let Some((width, height, x, y)) = parse_geometry(fields[2]) else { continue };
        result.push(Monitor {
            name: fields[fields.len() - 1].to_owned(),
            x,
            y,
            width,
            height,
            primary: fields[1].contains('*'),
        });
    }
    result
}

/// The workspaces i3 reports (`i3-msg -t get_workspaces`); empty without i3.
fn i3_workspaces() -> Vec<Object> {
    let Some(bytes) = output("i3-msg", &["-t", "get_workspaces"]) else { return Vec::new() };
    match qjson::from_json(&bytes) {
        Ok(Value::Array(items)) => items.iter().map(Value::to_object).collect(),
        _ => Vec::new(),
    }
}

/// `monitors` as `hyprctl -j monitors` prints them: scale 1, no transform (xrandr already gives
/// the rotated size), focused where i3's focused workspace is (else the primary monitor, else the
/// first), and `reserved` (left, top, right, bottom) as far as the visible workspace's rectangle
/// stays off the monitor's edges, which is the room bars take.
pub fn monitors_json_from(monitors: &[Monitor], workspaces: &[Object]) -> Vec<u8> {
    let focused_output = workspaces
        .iter()
        .find(|workspace| workspace.value("focused").to_bool(false))
        .map(|workspace| workspace.value("output").to_string_or(""))
        .filter(|name| monitors.iter().any(|monitor| monitor.name == *name))
        .or_else(|| monitors.iter().find(|monitor| monitor.primary).map(|monitor| monitor.name.clone()))
        .or_else(|| monitors.first().map(|monitor| monitor.name.clone()))
        .unwrap_or_default();
    let mut items = Vec::new();
    for monitor in monitors {
        let mut reserved = [0i32; 4];
        let visible = workspaces.iter().find(|workspace| {
            workspace.value("visible").to_bool(false) && workspace.value("output").to_string_or("") == monitor.name
        });
        if let Some(workspace) = visible {
            let rect = workspace.value("rect").to_object();
            let (x, y) = (rect.value("x").to_int(monitor.x), rect.value("y").to_int(monitor.y));
            let (width, height) = (rect.value("width").to_int(monitor.width), rect.value("height").to_int(monitor.height));
            reserved = [
                (x - monitor.x).max(0),
                (y - monitor.y).max(0),
                (monitor.x + monitor.width - x - width).max(0),
                (monitor.y + monitor.height - y - height).max(0),
            ];
        }
        let mut object = Object::new();
        object.insert("name", monitor.name.as_str());
        object.insert("x", monitor.x);
        object.insert("y", monitor.y);
        object.insert("width", monitor.width);
        object.insert("height", monitor.height);
        object.insert("scale", 1.0);
        object.insert("transform", 0);
        object.insert("focused", monitor.name == focused_output);
        object.insert("disabled", false);
        object.insert("reserved", reserved.iter().map(|&edge| Value::from(edge)).collect::<Vec<Value>>());
        items.push(Value::Object(object));
    }
    Value::Array(items).to_json(Format::Compact).into_bytes()
}

/// The X11 monitors as `hyprctl -j monitors` prints Hyprland's; `None` when xrandr does not
/// answer or lists none.
pub fn monitors_json() -> Option<Vec<u8>> {
    let monitors = parse_active_monitors(&String::from_utf8_lossy(&output("xrandr", &["--listactivemonitors"])?));
    if monitors.is_empty() {
        return None;
    }
    Some(monitors_json_from(&monitors, &i3_workspaces()))
}

/// The keyboard in what `setxkbmap -query` printed (`rules:`, `model:`, `layout:`, `variant:`
/// and `options:` lines); `None` without a layout. X11 has one core keymap, so it is the main
/// keyboard and there are no others. The first layout is taken as the active one.
pub fn keyboards_from_query(text: &str) -> Option<Keyboards> {
    let mut names = KeyboardNames { name: "x11".into(), ..KeyboardNames::default() };
    for line in text.lines() {
        let Some((key, value)) = line.split_once(':') else { continue };
        let value = value.trim().to_owned();
        match key.trim() {
            "rules" => names.rules = value,
            "model" => names.model = value,
            "layout" => names.layout = value,
            "variant" => names.variant = value,
            "options" => names.options = value,
            _ => {}
        }
    }
    if names.layout.is_empty() {
        return None;
    }
    Some(Keyboards { main: names, others: Vec::new() })
}

/// The X11 keyboard ([`keyboards_from_query`]); `None` when setxkbmap does not answer.
pub fn keyboards() -> Option<Keyboards> {
    keyboards_from_query(&String::from_utf8_lossy(&output("setxkbmap", &["-query"])?))
}

#[link(name = "X11")]
unsafe extern "C" {
    fn XOpenDisplay(name: *const c_char) -> *mut c_void;
    fn XCloseDisplay(display: *mut c_void) -> c_int;
    fn XDefaultRootWindow(display: *mut c_void) -> c_ulong;
    fn XQueryPointer(
        display: *mut c_void,
        window: c_ulong,
        root: *mut c_ulong,
        child: *mut c_ulong,
        root_x: *mut c_int,
        root_y: *mut c_int,
        window_x: *mut c_int,
        window_y: *mut c_int,
        mask: *mut c_uint,
    ) -> c_int;
}

/// A display connection of its own (`$DISPLAY`) that asks where the pointer is. Xlib is used
/// from one thread per connection, so each sampling thread opens its own.
pub struct Pointer {
    display: *mut c_void,
    root: c_ulong,
}

// SAFETY: the connection is only used by whoever owns the `Pointer`, one call at a time.
unsafe impl Send for Pointer {}

impl Pointer {
    /// `None` when the display can't be opened.
    pub fn open() -> Option<Pointer> {
        // SAFETY: a null name opens `$DISPLAY`; the result is null or a connection owned here.
        let display = unsafe { XOpenDisplay(std::ptr::null()) };
        if display.is_null() {
            return None;
        }
        // SAFETY: an open connection.
        let root = unsafe { XDefaultRootWindow(display) };
        Some(Pointer { display, root })
    }

    /// Where the pointer is on the root window; `None` when it is on another screen.
    pub fn position(&self) -> Option<PointF> {
        let (mut root, mut child) = (0, 0);
        let (mut root_x, mut root_y, mut window_x, mut window_y) = (0, 0, 0, 0);
        let mut mask = 0;
        // SAFETY: an open connection and pointers to locals.
        let same_screen = unsafe {
            XQueryPointer(
                self.display,
                self.root,
                &mut root,
                &mut child,
                &mut root_x,
                &mut root_y,
                &mut window_x,
                &mut window_y,
                &mut mask,
            )
        };
        (same_screen != 0).then(|| PointF::new(f64::from(root_x), f64::from(root_y)))
    }
}

impl Drop for Pointer {
    fn drop(&mut self) {
        // SAFETY: the connection opened in `open`, closed once.
        unsafe { XCloseDisplay(self.display) };
    }
}

/// Where the pointer is now, asked once on a new connection.
pub fn pointer_position() -> Option<PointF> {
    Pointer::open()?.position()
}

/// The gpu-screen-recorder to run: the one on `PATH`, else Omaxian's Flatpak wrapper
/// (`omarchy-gpu-screen-recorder`), which takes the same arguments.
pub fn gsr_program() -> &'static str {
    if omareel_core::compat::qstandardpaths::find_executable("gpu-screen-recorder").is_empty()
        && !omareel_core::compat::qstandardpaths::find_executable("omarchy-gpu-screen-recorder").is_empty()
    {
        "omarchy-gpu-screen-recorder"
    } else {
        "gpu-screen-recorder"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn active_monitors_parse() {
        let text = "Monitors: 2\n 0: +*DP-1 2560/597x1440/336+0+0  DP-1\n 1: +HDMI-1 1920/527x1080/296+2560+0  HDMI-1\n";
        let monitors = parse_active_monitors(text);
        assert_eq!(monitors.len(), 2);
        assert_eq!(
            monitors[0],
            Monitor { name: "DP-1".into(), x: 0, y: 0, width: 2560, height: 1440, primary: true }
        );
        assert_eq!(monitors[1].name, "HDMI-1");
        assert_eq!((monitors[1].x, monitors[1].width, monitors[1].primary), (2560, 1920, false));
        assert!(parse_active_monitors("").is_empty());
        assert!(parse_active_monitors("Monitors: 1\n 0: +X garbage  X\n").is_empty());
    }

    #[test]
    fn monitors_print_like_hyprctl() {
        let monitors = parse_active_monitors("Monitors: 2\n 0: +*A 100/1x50/1+0+0  A\n 1: +B 200/1x100/1+100+0  B\n");
        let workspaces = match qjson::from_json(
            br#"[{"focused":true,"visible":true,"output":"B","rect":{"x":100,"y":10,"width":200,"height":80}},
                 {"focused":false,"visible":true,"output":"A","rect":{"x":0,"y":0,"width":100,"height":50}}]"#,
        ) {
            Ok(Value::Array(items)) => items.iter().map(Value::to_object).collect::<Vec<_>>(),
            _ => unreachable!(),
        };
        let json = monitors_json_from(&monitors, &workspaces);
        let Ok(Value::Array(items)) = qjson::from_json(&json) else { panic!("not an array") };
        let b = items[1].to_object();
        assert_eq!(b.value("name").to_string_or(""), "B");
        assert!(b.value("focused").to_bool(false));
        assert!(!items[0].to_object().value("focused").to_bool(true));
        let reserved: Vec<i32> = b.value("reserved").to_array().iter().map(|v| v.to_int(-1)).collect();
        assert_eq!(reserved, [0, 10, 0, 10]);
        // Without i3 the primary monitor is the focused one.
        let json = monitors_json_from(&monitors, &[]);
        let Ok(Value::Array(items)) = qjson::from_json(&json) else { panic!("not an array") };
        assert!(items[0].to_object().value("focused").to_bool(false));
    }

    #[test]
    fn keyboards_from_setxkbmap() {
        let keyboards =
            keyboards_from_query("rules:      evdev\nmodel:      pc105\nlayout:     us,it\nvariant:    ,\noptions:    grp:alt_shift_toggle\n")
                .unwrap();
        assert_eq!(keyboards.main.layout, "us,it");
        assert_eq!(keyboards.main.options, "grp:alt_shift_toggle");
        assert_eq!(keyboards.main.rules, "evdev");
        assert!(keyboards.others.is_empty());
        assert!(keyboards_from_query("rules: evdev\n").is_none());
    }
}
