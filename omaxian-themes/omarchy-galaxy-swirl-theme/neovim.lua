return {
  {
    "omacom/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      colors = {
        bg         = "#030002",
        dark_bg    = "#020002",
        darker_bg  = "#020001",
        lighter_bg = "#1c1a1b",

        fg         = "#F7DCE5",
        dark_fg    = "#b9a5ac",
        light_fg   = "#f8e1e9",
        bright_fg  = "#f9e5ec",
        muted      = "#5d585c",

        red        = "#c17b8e",
        yellow     = "#ffcbc5",
        orange     = "#421727",
        green      = "#ffa595",
        cyan       = "#f7bbff",
        blue       = "#9f6698",
        purple     = "#df89b8",
        brown      = "#79565f",

        bright_red    = "#e28aa2",
        bright_yellow = "#ffc5be",
        bright_green  = "#ffb29e",
        bright_cyan   = "#ffcbff",
        bright_blue   = "#bc76b4",
        bright_purple = "#ff95d3",

        accent               = "#9f6698",
        cursor               = "#F7DCE5",
        foreground           = "#F7DCE5",
        background           = "#030002",
        selection             = "#1c1a1b",
        selection_foreground = "#F7DCE5",
        selection_background = "#1c1a1b",
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}
