---
name: omaview
description: Inspect a picture, video or music file and grab exact frames with Omaview, Omarchy's picture viewer and media player, without a display. Use when asked what's in a video (duration, codecs, tracks, languages, chapters), about a photo (dimensions, format, when and with what camera it was taken), for a still from a video at a time, or to open something for the user to look at.
---

# Omaview

Omaview is Omarchy's picture viewer and media player. Its commands below need no display; each takes `--json`, exits 0 on success and 1 on failure with the reason on stderr, and prints English whatever the desktop's language.

## What's in a file

```bash
omaview info movie.mkv --json
omaview info photo.jpg --json
```

For a video or song: `duration` (seconds), `format`, `size`, every stream (`type` video, audio or subtitle; `codec`; `language`; `title`; `width`, `height` and `frameRate` for video; `channels` for audio; `text` for subtitles, false for bitmap ones Omaview can't show), `chapters` with `start`, `end` and `title`, and `resume`: the second Omaview would resume at, or null.

For a picture: `type` is `picture`, with `format`, `width` and `height` as shown (the EXIF orientation applied), `size` in bytes, `frames` and `animated`, `transparent`, and what the camera wrote, when it did: `taken` (ISO 8601, the camera's own clock), `camera`, `lens`, `exposure` (seconds), `aperture`, `iso`, `focalLength` (mm).

## A frame at a time

```bash
omaview frame movie.mkv --at 1:02:03.5 -o still.png --json
```

The exact frame at that time, at the video's own resolution, as a PNG. `--at` takes seconds (`90`), `mm:ss` or `hh:mm:ss.mmm`.

## Showing something to the user

```bash
omaview open photo.jpg          # one file opens with its folder to step through
omaview open a.mkv b.jpg        # several files are the playlist, in that order
```

This opens a window on the user's desktop; only do it when they asked to see something.

Anything else — converting, resizing, cutting, extracting audio, changing containers — is ffmpeg's job (or ImageMagick's for pictures); use them directly. Cutting a clip by hand is Omacut's (`omacut file`), drawing on a picture Omasnap's (`omasnap file`).
