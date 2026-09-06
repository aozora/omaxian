return {
  {
    "omacom/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      colors = {
        bg         = "#010608",
        dark_bg    = "#010506",
        darker_bg  = "#010304",
        lighter_bg = "#1a1f21",

        fg         = "#A6D5D0",
        dark_fg    = "#7da09c",
        light_fg   = "#b3dbd7",
        bright_fg  = "#bce0dc",
        muted      = "#61696b",

        red        = "#7d9b8b",
        yellow     = "#c3fcf1",
        orange     = "#91aa9c",
        green      = "#9acbc6",
        cyan       = "#a4e4ea",
        blue       = "#5f8491",
        purple     = "#88afc8",
        brown      = "#57665e",

        bright_red    = "#8db39e",
        bright_yellow = "#bafff5",
        bright_green  = "#a5e5df",
        bright_cyan   = "#aefeff",
        bright_blue   = "#6c9aab",
        bright_purple = "#94c6e7",

        accent               = "#5f8491",
        cursor               = "#A6D5D0",
        foreground           = "#A6D5D0",
        background           = "#010608",
        selection             = "#1a1f21",
        selection_foreground = "#A6D5D0",
        selection_background = "#1a1f21",
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
