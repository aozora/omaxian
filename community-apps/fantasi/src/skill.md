---
name: fantasi
description: Make images on this machine with a local model through Fantasi's command line. Use when a task needs an image made rather than found, such as a website's hero image, a placeholder illustration, a game sprite, an app icon idea or a desktop background, and the user hasn't asked for a cloud service.
---

# Fantasi

`fantasi generate` makes one image with the local image model Omarchy runs, saves it as a PNG, and prints where.

```sh
fantasi generate "a calm mountain lake at dusk, navy and teal, mist over the water"
fantasi generate "flat app icon of a paper boat on a teal circle" --width 1024 --height 1024 --json
```

- It prints the path on success (`{"path": "…"}` with `--json`) and exits 0; on failure it says why on stderr after `Error:` and exits 1.
- Images go to `~/Pictures/Generated`, named by time and the prompt's first words. Copy the file where the project needs it; don't move it, since the user browses that folder in Fantasi.
- An image takes about half a minute. Make them one at a time; the model runs one job at once.
- To change a picture rather than make a new one, pass it with `--from` and say what should change: `fantasi generate "include a red balloon" --from ~/Pictures/Generated/….png`. With an edit model, which Omarchy recommends, the prompt is the instruction and the rest of the picture stays as it is. `--from` takes any picture, a photo too; it's scaled and cut from the middle to a size near a megapixel in its own shape.
- With an edit model, give `--from` up to four times to combine pictures, naming them in order: `fantasi generate "put the cabin from the first image beside the lighthouse from the second" --from cabin.png --from lighthouse.png`. The new image takes the first picture's shape.
- Options: `--width` and `--height` in pixels (multiples of 64 up to about a megapixel work best: 1024×1024, 1344×768, 768×1344), `--steps` (the model's own default when left out), `--seed` for a repeatable image.
- Write the prompt as a description of the picture: subject, setting, light, colors, composition. Say "no text" when the image must not contain lettering.

When it says no image model is running, tell the user and show the command it suggests (`omarchy-models start …` or `omarchy-models use …`). Don't start or install one yourself: it can stop a text model the user is relying on.

The images belong to the user. Mention the path of every image you make.
- With a video model running, `fantasi generate --video "<what happens>"` makes a 5-second clip with sound (`--seconds` takes 2, 10, 15 or longer, as long as the model makes on that machine), as a WebM beside a poster PNG; add `--from <picture>` to start the clip from that picture. A 2-second clip takes about three minutes, longer ones more.
- With a music model running, `fantasi generate --music "<the song: its style, mood, instruments and voice>"` makes a one-minute song, as an MP3 in `~/Music/Generated`. Give its words with `--lyrics "[verse]\n…\n[chorus]\n…"`, or `--instrumental` for none; left to itself the model writes lyrics that fit the style but rarely the subject. `--seconds` sets its length, up to 600. A song takes about a minute.
