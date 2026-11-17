#pragma once

#include <QString>
#include <QStringList>

namespace playlist {

// What a file is, by its extension.
enum class Kind { None, Picture, Video, Audio };
Kind kind(const QString &path);

bool picture(const QString &path);

// The files in a file's folder that belong with it, the file among them, in
// natural order (2 before 10). Videos go with everything, but songs and
// pictures don't mix: a folder of photos doesn't play its voice memos, and an
// album doesn't show its cover.jpg as a track.
QStringList siblings(const QString &path);
// A folder's files, in natural order: its pictures and videos when it has
// more pictures than songs, as a camera's does, and otherwise its songs and
// videos, so an album's cover isn't one of its tracks.
QStringList folder(const QString &directory);

}  // namespace playlist
