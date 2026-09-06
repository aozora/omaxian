return {
  {
    "omacom/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      colors = {
        bg         = "#0B0517",
        dark_bg    = "#080411",
        darker_bg  = "#06030c",
        lighter_bg = "#231e2e",

        fg         = "#E9D6E7",
        dark_fg    = "#afa1ad",
        light_fg   = "#ecdceb",
        bright_fg  = "#efe0ed",
        muted      = "#605f65",

        red        = "#b582b1",
        yellow     = "#ffcdff",
        orange     = "#c095bd",
        green      = "#a0c2ff",
        cyan       = "#c6d0ff",
        blue       = "#8773b5",
        purple     = "#c695e2",
        brown      = "#735971",

        bright_red    = "#d292ce",
        bright_yellow = "#ffc3ff",
        bright_green  = "#acd7ff",
        bright_cyan   = "#d9e4ff",
        bright_blue   = "#9e84d6",
        bright_purple = "#e3a4ff",

        accent               = "#8773b5",
        cursor               = "#E9D6E7",
        foreground           = "#E9D6E7",
        background           = "#0B0517",
        selection             = "#231e2e",
        selection_foreground = "#E9D6E7",
        selection_background = "#231e2e",
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
