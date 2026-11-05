# Placing items with signed sign

`signed sign <pdf> <output> --items items.json` writes a signed copy of the PDF
with each item drawn on its page. The original is never changed. Items can
also be passed one at a time with `--item '<json>'`, or on standard input
with `--items -`.

The items file is a JSON array, or an object with an `"items"` array:

```json
[
  {"signature": "Alex Morgan", "page": 4, "x": 100, "bottom": 288, "width": 160},
  {"text": "Alex Morgan", "page": 4, "x": 104, "bottom": 356},
  {"date": true, "page": 4, "x": 456, "bottom": 288, "size": 11}
]
```

## Positions

Every position is in points (1/72 inch), measured from the top-left corner of
the page as it is displayed, the way `signed pages`, `signed text`, and
`signed render --grid` report them. Pages are counted from 1.

- `page`: the page to place the item on.
- `x`: the item's left edge.
- `y` or `bottom`: the item's top edge, or its bottom edge. Use `bottom` to
  stand an item on a line: set it a point or two above the line.

An item must fit on its page; one that would reach past an edge is refused.

## Kinds

- **Signature**: `"signature": "<name>"`, one of the names `signed
  signatures` lists. Give `width` or `height` in points and the other follows
  from the signature's shape. With neither, it is as wide as the last time it
  was resized in the app, or 108 points (an inch and a half). A signature
  across a signature line is usually 120 to 180 points wide.
- **Text**: `"text": "<text>"`, with `\n` for a new line. `size` is the font
  size in points, from 4 to 144 (default 12, or the size last used in the app).
  Text is set in Noto Sans and stays real, selectable text in the PDF.
- **Date**: `"date": true` places today's date in the system's short format
  with a four-digit year, such as 10/14/2026. It takes `size` like text. Pass
  `"text"` instead to write a specific date.

## Finding where things go

1. `signed text <pdf> --page N` prints each line of text with its box. A form's
   labels ("Signature", "Date", "Name") locate the blanks next to them; the
   line to write on is usually just above a label printed under it, or to the
   right of a label printed beside it.
2. `signed render <pdf> --page N --grid -o page.png` draws a grid every 50
   points, labeled every 100, so you can read positions for lines and boxes
   that aren't text.
3. After signing, render the page of the output and look at it. Move anything
   that sits off its line and sign again with `--force`.

`--json` prints what was placed, with each item's final box.
