# Privacy and security

[← README](../README.md)

The plugin runs unsandboxed inside `omarchy-shell`, like every Omarchy plugin.
That is worth taking seriously, so here is exactly what it does.

**It talks to three hosts, and no others.** `data.geo.admin.ch` and
`app-prod-ws.meteoswiss-app.ch` for weather; `ipapi.co` once, for the
first-run location. The list is enforced in code — `lib/Net.js` re-derives the
host from every finished URL and refuses anything else, and redirects are not
followed, so an allowlisted host cannot hand the request onward.

**Your searches never leave the machine.** Town search runs against the
bundled index. What you type is never part of a request, which is why there is
no query for anything to be injected into — and why search still works
offline.

**The only variable in any URL is a six-digit number.** Forecast requests
carry a postal-code point id validated against `^[0-9]{6}$`; the language is
an `Accept-Language` header drawn from a three-item list. Nothing else is
interpolated anywhere.

**No shell is ever invoked.** Every request is an argv array handed to
`curl` — there is no `sh -c`, so there is no quoting to get wrong. Requests
carry a connect timeout, a total timeout and a byte ceiling, and responses are
range-checked and length-capped before anything is drawn.

**Location detection is one request, at most once.** It runs only if
`detectLocation` is on, only when you have no favourites yet, and its answer
is cached so it never runs again. Only latitude, longitude and country code
are read; your IP address is not stored. Set `detectLocation` to `false` to
switch it off entirely — see *Where it starts* in the [manual](manual.md) for
what happens then.

**It launches two other programs**, and only for one purpose each.
`omarchy-notification-send`, when a new warning meets the bar in the manual and
you have switched notifications on: the headline and body are MeteoSwiss text
already stripped of control characters and length-capped, the click command is
a literal constant, and the whole thing is handed over as an argv array — no
part of a warning can become a command. And `xdg-open`, when you click a link.

`Net.openCommand` accepts nothing but a URL that is verbatim one of the four
literal attribution links; one of the fifteen map pages, decided by rebuilding
all fifteen and comparing, optionally carrying the weather-cam fragment for one
station on the one page where that fragment means something; or one built by
`localForecastUrl` and matching its shape exactly — one of three known hosts,
that host's own path prefix, a slug of `[a-z0-9-]`, and a four-digit postal
code with nothing after it. Appending a segment, changing the host, or passing
any other string all yield nothing. The three page hosts are deliberately *not*
on the fetch allowlist: the plugin opens those pages in a browser and never
reads them.

**It writes one file**, its own state under
`~/.local/state/omarchy/plugins/jmaeder.swissweather/`, and reads only that
plus its own bundled data.

**Remote text carries no markup.** MeteoSwiss warnings arrive as strings; the
HTML the service also sends is dropped, control characters are stripped, and
every label is a `Text.PlainText` item. The one exception is the body of a
warning, where the plugin emboldens the labels MeteoSwiss wrote ("Possible
impacts:", "Expected amounts:") to make it scannable — there the plugin writes
the markup itself and every character from the network goes through
`Model.escapeMarkup` first, so a payload containing `<b>` or `<img src=x>` is
displayed as those literal characters.

**The warning links are read, never kept.** The type numbering MeteoSwiss uses
is not published, so the hazard is identified from the "what to do" link that
comes with each warning — but the URL is not stored: its path is cut into
segments, each is looked up in a fixed table, and what is kept is one of
thirteen hazard keys or nothing.
