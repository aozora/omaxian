#include "filetree.h"

#include <QCollator>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <algorithm>
#include <filesystem>
#include <system_error>

// A name in a folder, right at the root too ("/" + "etc", not "//etc").
static QString joined(const QString &folder, const QString &name) {
    return QDir::cleanPath(folder + "/" + name);
}

static QString cleaned(const QString &path) {
    return QDir::cleanPath(QFileInfo(path).absoluteFilePath());
}

FileTree::FileTree(QObject *parent) : QAbstractListModel(parent) {
    // Saving a file is several changes in a row (a temporary file, a rename).
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(150);
    connect(&m_debounce, &QTimer::timeout, this, &FileTree::rebuild);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_debounce, qOverload<>(&QTimer::start));
}

void FileTree::setRoot(const QString &root) {
    const QString clean = root.isEmpty() ? QString() : QDir::cleanPath(QFileInfo(root).absoluteFilePath());
    if (clean == m_root)
        return;
    m_root = clean;
    m_expanded.clear();
    // Inside a hidden folder, its neighbours are what the user came for.
    const bool inHidden = clean.split('/', Qt::SkipEmptyParts).filter(QRegularExpression("^\\.")).size() > 0;
    if (inHidden != m_showHidden) {
        m_showHidden = inHidden;
        emit showHiddenChanged();
    }
    rebuild();
    emit rootChanged();
}

void FileTree::setShowHidden(bool show) {
    if (show == m_showHidden)
        return;
    m_showHidden = show;
    rebuild();
    emit showHiddenChanged();
}

int FileTree::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant FileTree::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};
    const Entry &entry = m_rows.at(index.row());
    switch (role) {
    case NameRole: return entry.name;
    case PathRole: return entry.path;
    case DepthRole: return entry.depth;
    case FolderRole: return entry.folder;
    case ExpandedRole: return entry.folder && m_expanded.contains(entry.path);
    case HiddenRole: return entry.name.startsWith('.');
    }
    return {};
}

QHash<int, QByteArray> FileTree::roleNames() const {
    return {{NameRole, "name"}, {PathRole, "path"}, {DepthRole, "depth"},
            {FolderRole, "folder"}, {ExpandedRole, "expanded"}, {HiddenRole, "hidden"}};
}

QVector<FileTree::Entry> FileTree::rowsUnder(const QString &folder, int depth) const {
    QDir::Filters filters = QDir::AllEntries | QDir::NoDotAndDotDot;
    if (m_showHidden)
        filters |= QDir::Hidden;
    QFileInfoList infos = QDir(folder).entryInfoList(filters);
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(infos.begin(), infos.end(), [&](const QFileInfo &a, const QFileInfo &b) {
        if (a.isDir() != b.isDir())
            return a.isDir();
        return collator.compare(a.fileName(), b.fileName()) < 0;
    });

    QVector<Entry> rows;
    for (const QFileInfo &info : infos) {
        const Entry entry{info.fileName(), info.absoluteFilePath(), depth, info.isDir()};
        rows << entry;
        if (entry.folder && m_expanded.contains(entry.path))
            rows << rowsUnder(entry.path, depth + 1);
    }
    return rows;
}

void FileTree::rebuild() {
    // Folders removed from disk stop being open, so they don't come back open.
    for (auto it = m_expanded.begin(); it != m_expanded.end();)
        it = QFileInfo(*it).isDir() ? std::next(it) : m_expanded.erase(it);
    const QVector<Entry> rows = m_root.isEmpty() ? QVector<Entry>() : rowsUnder(m_root, 0);

    // Only the rows between the unchanged start and end are replaced. A
    // reset would scroll the list back to its top on every save in a shown
    // folder, and drop a click or drag in progress with its row.
    auto same = [](const Entry &a, const Entry &b) {
        return a.path == b.path && a.depth == b.depth && a.folder == b.folder;
    };
    qsizetype head = 0;
    while (head < m_rows.size() && head < rows.size() && same(m_rows.at(head), rows.at(head)))
        ++head;
    qsizetype tail = 0;
    while (tail < m_rows.size() - head && tail < rows.size() - head
           && same(m_rows.at(m_rows.size() - 1 - tail), rows.at(rows.size() - 1 - tail)))
        ++tail;
    if (const qsizetype gone = m_rows.size() - tail - head; gone > 0) {
        beginRemoveRows({}, int(head), int(head + gone - 1));
        m_rows.remove(head, gone);
        endRemoveRows();
    }
    if (const qsizetype added = rows.size() - tail - head; added > 0) {
        beginInsertRows({}, int(head), int(head + added - 1));
        m_rows = m_rows.mid(0, head) + rows.mid(head, added) + m_rows.mid(head);
        endInsertRows();
    }
    // Rows that stayed can still have opened or closed.
    if (!m_rows.isEmpty())
        emit dataChanged(index(0), index(int(m_rows.size()) - 1), {ExpandedRole});
    rewatch();
    emit refreshed();
}

void FileTree::rewatch() {
    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());
    QStringList folders;
    if (!m_root.isEmpty())
        folders << m_root;
    for (const QString &folder : m_expanded)
        folders << folder;
    if (!folders.isEmpty())
        m_watcher.addPaths(folders);
}

void FileTree::toggle(int row) {
    if (isExpanded(row))
        collapse(row);
    else
        expand(row);
}

void FileTree::expand(int row) {
    if (!isFolder(row) || isExpanded(row))
        return;
    const Entry entry = m_rows.at(row);
    m_expanded.insert(entry.path);
    const QVector<Entry> children = rowsUnder(entry.path, entry.depth + 1);
    if (!children.isEmpty()) {
        // In one go: one at a time shifts the rows after it once per child.
        beginInsertRows({}, row + 1, row + int(children.size()));
        m_rows = m_rows.mid(0, row + 1) + children + m_rows.mid(row + 1);
        endInsertRows();
    }
    const QModelIndex at = index(row);
    emit dataChanged(at, at, {ExpandedRole});
    rewatch();
}

void FileTree::collapse(int row) {
    if (!isExpanded(row))
        return;
    const int depth = m_rows.at(row).depth;
    int end = row + 1;
    while (end < m_rows.size() && m_rows.at(end).depth > depth)
        ++end;
    // Folders inside close with it, so it opens the way it was first shown.
    for (int i = row; i < end; ++i)
        m_expanded.remove(m_rows.at(i).path);
    if (end > row + 1) {
        beginRemoveRows({}, row + 1, end - 1);
        m_rows.remove(row + 1, end - row - 1);
        endRemoveRows();
    }
    const QModelIndex at = index(row);
    emit dataChanged(at, at, {ExpandedRole});
    rewatch();
}

bool FileTree::inTree(const QString &clean) const {
    return !m_root.isEmpty() && clean != m_root && clean.startsWith(m_root == "/" ? m_root : m_root + "/");
}

int FileTree::reveal(const QString &path) {
    if (path.isEmpty())
        return -1;
    const QString clean = cleaned(path);
    if (!inTree(clean))
        return -1;
    // Each folder between the root and the file, from the top down.
    const QStringList parts = QDir(m_root).relativeFilePath(clean).split('/');
    QString folder = m_root;
    for (int i = 0; i + 1 < parts.size(); ++i) {
        folder = joined(folder, parts.at(i));
        const int row = indexOf(folder);
        if (row < 0)
            return -1;
        expand(row);
    }
    return indexOf(clean);
}

int FileTree::indexOf(const QString &path) const {
    const QString clean = QDir::cleanPath(QFileInfo(path).absoluteFilePath());
    for (int i = 0; i < m_rows.size(); ++i)
        if (m_rows.at(i).path == clean)
            return i;
    return -1;
}

int FileTree::parentOf(int row) const {
    if (row < 0 || row >= m_rows.size())
        return -1;
    const int depth = m_rows.at(row).depth;
    for (int i = row - 1; i >= 0; --i)
        if (m_rows.at(i).depth < depth)
            return i;
    return -1;
}

bool FileTree::isFolder(int row) const {
    return row >= 0 && row < m_rows.size() && m_rows.at(row).folder;
}

bool FileTree::isExpanded(int row) const {
    return isFolder(row) && m_expanded.contains(m_rows.at(row).path);
}

QString FileTree::pathAt(int row) const {
    return row >= 0 && row < m_rows.size() ? m_rows.at(row).path : QString();
}

QString FileTree::trash(const QString &target) {
    // By path, not row: the rows can be rebuilt from disk while Delete asks.
    const QString path = cleaned(target);
    if (target.isEmpty() || !inTree(path) || !(QFileInfo::exists(path) || QFileInfo(path).isSymLink()))
        return tr("Nothing to delete");
    QFile file(path);
    if (!file.moveToTrash())
        return file.errorString().isEmpty() ? tr("It couldn't be moved to the trash") : file.errorString();
    m_debounce.stop();
    rebuild();
    return {};
}

QString FileTree::nameProblem(const QString &folder, const QString &name) const {
    if (name.trimmed().isEmpty())
        return tr("Give it a name");
    if (name.contains('/') || name == "." || name == "..")
        return tr("A name can't be . or .. or have a / in it");
    if (QFileInfo::exists(joined(folder, name)) || QFileInfo(joined(folder, name)).isSymLink())
        return tr("%1 already exists here").arg(name);
    return {};
}

QVariantMap FileTree::move(const QString &source, const QString &folder) {
    // By path, not row: the rows can be rebuilt from disk mid-drag.
    const QString from = cleaned(source);
    if (source.isEmpty() || !inTree(from) || !(QFileInfo::exists(from) || QFileInfo(from).isSymLink()))
        return {{"error", tr("Nothing to move")}};
    const QString into = cleaned(folder);
    if (!QFileInfo(into).isDir())
        return {{"error", tr("%1 isn't a folder").arg(into)}};
    if (QFileInfo(from).absolutePath() == into)
        return {{"path", from}};
    if (into == from || into.startsWith(from + "/"))
        return {{"error", tr("A folder can't go inside itself")}};
    const QString name = QFileInfo(from).fileName();
    if (const QString problem = nameProblem(into, name); !problem.isEmpty())
        return {{"error", problem}};
    // A rename, so a folder moves whole and a file keeps its links and
    // permissions. Across file systems it fails rather than half-copying.
    const QString to = joined(into, name);
    if (!QDir().rename(from, to))
        return {{"error", tr("%1 couldn't be moved there").arg(name)}};
    followExpanded(from, to);
    if (into != m_root)
        m_expanded.insert(into);
    m_debounce.stop();
    rebuild();
    return {{"path", to}};
}

QString FileTree::folderAt(int row) const {
    if (row < 0 || row >= m_rows.size())
        return m_root;
    const Entry &entry = m_rows.at(row);
    return entry.folder ? entry.path : QFileInfo(entry.path).absolutePath();
}

QVariantMap FileTree::create(const QString &folder, const QString &name, bool isFolder) {
    if (const QString problem = nameProblem(folder, name); !problem.isEmpty())
        return {{"error", problem}};
    const QString path = joined(folder, name);
    bool made;
    if (isFolder) {
        made = QDir().mkdir(path);
    } else {
        QFile file(path);
        // NewOnly, so a file that appeared since the check is never truncated.
        made = file.open(QIODevice::WriteOnly | QIODevice::NewOnly);
    }
    if (!made)
        return {{"error", tr("%1 couldn't be created here").arg(name)}};
    if (QDir::cleanPath(folder) != m_root)
        m_expanded.insert(QDir::cleanPath(folder));
    m_debounce.stop();
    rebuild();
    return {{"path", path}};
}

int FileTree::find(const QString &prefix, int from) const {
    const int count = int(m_rows.size());
    for (int i = 0; i < count; ++i) {
        const int row = ((from + i) % count + count) % count;
        if (m_rows.at(row).name.startsWith(prefix, Qt::CaseInsensitive))
            return row;
    }
    return -1;
}

void FileTree::followExpanded(const QString &from, const QString &to) {
    QSet<QString> expanded;
    for (const QString &folder : std::as_const(m_expanded))
        expanded << (folder == from ? to : folder.startsWith(from + "/") ? to + folder.mid(from.size()) : folder);
    m_expanded = expanded;
}

QVariantMap FileTree::rename(const QString &source, const QString &name) {
    const QString from = cleaned(source);
    if (source.isEmpty() || !inTree(from) || !(QFileInfo::exists(from) || QFileInfo(from).isSymLink()))
        return {{"error", tr("Nothing to rename")}};
    if (name == QFileInfo(from).fileName())
        return {{"path", from}};
    const QString folder = QFileInfo(from).absolutePath();
    if (const QString problem = nameProblem(folder, name); !problem.isEmpty())
        return {{"error", problem}};
    const QString to = joined(folder, name);
    if (!QDir().rename(from, to))
        return {{"error", tr("%1 couldn't be renamed").arg(QFileInfo(from).fileName())}};
    followExpanded(from, to);
    m_debounce.stop();
    rebuild();
    return {{"path", to}};
}

QVariantMap FileTree::duplicate(const QString &source) {
    const QString from = cleaned(source);
    const QFileInfo info(from);
    if (source.isEmpty() || !inTree(from) || !(info.exists() || info.isSymLink()))
        return {{"error", tr("Nothing to duplicate")}};
    // "bindings.lua" becomes "bindings copy.lua"; a folder or a dotfile
    // keeps its whole name before " copy".
    const QString name = info.fileName();
    const qsizetype dot = info.isDir() ? -1 : name.lastIndexOf('.');
    const QString stem = dot > 0 ? name.left(dot) : name;
    const QString suffix = dot > 0 ? name.mid(dot) : QString();
    QString to;
    for (int n = 1; to.isEmpty() || QFileInfo::exists(to) || QFileInfo(to).isSymLink(); ++n)
        to = joined(info.absolutePath(), stem + (n == 1 ? tr(" copy") : tr(" copy %1").arg(n)) + suffix);
    // A link duplicates as a copy of what it points to: another link to the
    // same file would make editing "the copy" change the original. Never over
    // anything: copy refuses an existing name. Links inside a folder are
    // copied as links.
    const QString original = info.isSymLink() ? info.canonicalFilePath() : from;
    if (original.isEmpty())
        return {{"error", tr("%1 points at nothing to duplicate").arg(name)}};
    // A link to a folder the copy would land in would copy itself forever.
    const QString copyIn = QFileInfo(info.absolutePath()).canonicalFilePath();
    if (copyIn == original || copyIn.startsWith(original + "/"))
        return {{"error", tr("%1 can't be duplicated inside itself").arg(name)}};
    std::error_code error;
    std::filesystem::copy(QFile::encodeName(original).constData(), QFile::encodeName(to).constData(),
                          std::filesystem::copy_options::recursive | std::filesystem::copy_options::copy_symlinks,
                          error);
    if (error)
        return {{"error", tr("%1 couldn't be duplicated: %2").arg(name, QString::fromLocal8Bit(error.message().c_str()))}};
    m_debounce.stop();
    rebuild();
    return {{"path", to}};
}
