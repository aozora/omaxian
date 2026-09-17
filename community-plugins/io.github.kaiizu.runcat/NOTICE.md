# Notices

Running Cat — a CPU-load cat for the Omarchy bar.
Copyright (C) 2026 Dani Cruz (kaiizu).

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. See `LICENSE` for the full text.

## Third-party assets

`assets/active/0.svg` … `assets/active/4.svg` and `assets/idle/0.svg` are the
sprite frame set from [gnome-runcat](https://github.com/win0err/gnome-runcat)
by Sergei Kolesnikov, used under the GPL-3.0. Two changes were made: the fill
color was set to `#ffffff` so the frames take the bar's tint exactly, and the
files were renamed to `0.svg`, `1.svg`, … gnome-runcat credits the cat images
to [RunCat for macOS](https://github.com/Kyome22/menubar_runcat) by Takuto
Nakamura, which is distributed under the Apache License 2.0.

## Third-party ideas

The concept — a cat running at a speed set by CPU load — is RunCat's, by
Takuto Nakamura, for the macOS menu bar. It was carried to GNOME by
gnome-runcat (Sergei Kolesnikov) and to KDE Plasma by
[CatWalk](https://store.kde.org/p/2137844/) (Yuri Saurov).

The animation model follows gnome-runcat's port of RunCat's: the cycle curve
`f(x) = 250 + 850 * (1 - x)^2` milliseconds per full cycle, a ticker that
re-arms to each frame boundary, and exponentially smoothed speed changes.

The widget code itself is original to this repository and written for the
Omarchy shell.
