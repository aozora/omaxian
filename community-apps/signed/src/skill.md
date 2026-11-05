---
name: signed
description: |
  Sign PDFs and fill them in with text and dates using Signed, with the
  person's saved, named signatures. Use for ANY request to sign a PDF, put a
  signature on a document, fill in a PDF form's blanks, date a document, or
  list, add, or remove saved signatures.
---

# Signed

Signed writes a signed copy of a PDF with signature images, text, and dates
placed on its pages. The original is never changed. No command needs a display.

Run `signed help items` first. It explains how to describe what to place and
where, for this version of Signed.

## Signing is the person's act

Only place a signature when the person asked you to sign with it, on the
document they named. If you're unsure which saved signature to use, which
blanks they want filled, or what to write in them, ask instead of guessing.

## Workflow

1. `signed signatures` lists the saved signatures by name. If the one needed is
   missing, ask the person for a scan or photo of it on white paper and add it
   with `signed add-signature "<name>" <image>`. Look at the saved PNG it prints;
   if paper is left around the ink, add it again with `--replace --threshold
   0.35`, or lower the threshold if strokes went missing.
2. `signed pages <pdf>` gives the page sizes. `signed text <pdf> --page N`
   prints the lines of text with their boxes, to find the labels of the blanks.
3. `signed render <pdf> --page N --grid -o /tmp/page.png`, then view the PNG,
   to see the lines and boxes and read their positions off the grid.
4. Write the items to a JSON file and run
   `signed sign <pdf> <pdf-name>-signed.pdf --items items.json`.
5. Render the signed page and view it. Fix anything off its line and sign again
   with `--force`.

## Working with the person

- Name the output `<original>-signed.pdf` beside the original unless told
  otherwise, as the app does.
- `signed open <pdf>` opens the app for them to adjust the placement by hand;
  it needs their desktop, so do not wait on it.
- Every command takes `--json`, exits 0 on success and 1 on failure, and writes
  errors to stderr. `signed help <command>` lists a command's options.
