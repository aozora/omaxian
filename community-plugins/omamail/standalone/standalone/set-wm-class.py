#!/usr/bin/python3
"""Set WM_CLASS on an X11 window: set-wm-class.py WINDOW_ID INSTANCE CLASS.

Quickshell windows always report class "quickshell", which no desktop entry
or dock can match to Omamail. Uses libX11 through ctypes (no extra packages).
"""
import ctypes
import sys

wid, instance, klass = int(sys.argv[1]), sys.argv[2], sys.argv[3]
x11 = ctypes.CDLL("libX11.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XInternAtom.restype = ctypes.c_ulong
x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
x11.XChangeProperty.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong,
                                ctypes.c_int, ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
x11.XFlush.argtypes = [ctypes.c_void_p]
display = x11.XOpenDisplay(None)
if not display:
    sys.exit("cannot open display")
data = instance.encode() + b"\0" + klass.encode() + b"\0"
XA_STRING = 31
x11.XChangeProperty(display, wid, x11.XInternAtom(display, b"WM_CLASS", 0), XA_STRING, 8, 0, data, len(data))
x11.XFlush(display)
