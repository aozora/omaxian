// Drives the real Main.qml against the real backend and short clips made by
// ffmpeg, offscreen, and fails on any QML warning. With OMAVIEW_SHOTS set to
// a directory, it also saves what the window looked like at each step.

#include <QDir>
#include <QFile>
#include <QMediaPlayer>
#include <QPainter>
#include <QVideoFrame>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QtTest>

#include "backend.h"
#include "filepicker.h"
#include "inhibit.h"
#include "theme.h"
#include "fixtures.h"
#include "thumbnails.h"
#include "translator.h"

namespace {

bool write(const QString &path, const QByteArray &contents) {
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(contents) == contents.size();
}

// A clip with a picture that changes, a tone, English subtitles and two chapters.
bool makeClip(const QString &directory, const QString &name, int seconds) {
    write(directory + "/subs.srt", "1\n00:00:00,300 --> 00:00:03,000\nWe kept driving until\nthe road ran out.\n\n"
                                   "2\n00:00:04,000 --> 00:00:07,000\nThen we walked.\n");
    const QByteArray split = QByteArray::number(std::min(4000, seconds * 500));
    write(directory + "/chapters.txt", ";FFMETADATA1\ntitle=Coast Road\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=" + split
                                           + "\ntitle=Leaving the city\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=" + split + "\nEND="
                                           + QByteArray::number(seconds * 1000) + "\ntitle=The coast road\n");
    QProcess ffmpeg;
    ffmpeg.setWorkingDirectory(directory);
    ffmpeg.start("ffmpeg", {"-v", "error", "-y", "-f", "lavfi", "-i",
                            QString("testsrc2=size=640x360:rate=25:duration=%1").arg(seconds), "-f", "lavfi", "-i",
                            QString("sine=frequency=440:duration=%1").arg(seconds), "-i", "subs.srt", "-i",
                            "chapters.txt", "-map", "0:v", "-map", "1:a", "-map", "2:s", "-map_metadata", "3",
                            "-map_chapters", "3", "-c:v", "libx264", "-g", "25", "-pix_fmt", "yuv420p", "-c:a", "aac", "-ac", "2",
                            "-c:s", "srt", "-metadata:s:a:0", "language=eng", "-metadata:s:s:0", "language=eng", name});
    return ffmpeg.waitForFinished(60000) && ffmpeg.exitCode() == 0;
}

class FakePicker : public FilePicker {
public:
    using FilePicker::FilePicker;
    void openMedia() override { ++opens; }
    void saveImage(const QUrl &url) override { suggested = url; }
    int opens = 0;
    QUrl suggested;
};

}  // namespace

class UiTests : public QObject {
    Q_OBJECT

    QTemporaryDir m_dir;
    QString m_clip;
    QString m_second;

    struct Window {
        std::unique_ptr<Translator> translator;
        std::unique_ptr<Theme> theme;
        std::unique_ptr<FakePicker> picker;
        std::unique_ptr<Backend> backend;
        std::unique_ptr<IdleInhibitor> idle;
        std::unique_ptr<QQmlApplicationEngine> engine;
        QQuickWindow *window = nullptr;
        QStringList warnings;
    };

    std::unique_ptr<Window> open(const QString &state) {
        auto w = std::make_unique<Window>();
        QDir().mkpath(state);
        w->translator = std::make_unique<Translator>(state + "/language");
        QCoreApplication::installTranslator(w->translator.get());
        w->theme = std::make_unique<Theme>(state);
        w->picker = std::make_unique<FakePicker>();
        Backend::Options options;
        options.positionsPath = state + "/positions.json";
        options.audio = false;
        options.picker = w->picker.get();
        options.previewDelayMs = 0;
        w->backend = std::make_unique<Backend>(options);
        w->idle = std::make_unique<IdleInhibitor>();
        w->engine = std::make_unique<QQmlApplicationEngine>();
        auto *warnings = &w->warnings;
        connect(w->engine.get(), &QQmlEngine::warnings, this, [warnings](const QList<QQmlError> &errors) {
            for (const auto &error : errors)
                *warnings << error.toString();
        });
        w->engine->rootContext()->setContextProperty("translator", w->translator.get());
        w->engine->rootContext()->setContextProperty("theme", w->theme.get());
        w->engine->rootContext()->setContextProperty("backend", w->backend.get());
        w->engine->rootContext()->setContextProperty("idle", w->idle.get());
        w->engine->addImageProvider("thumbnail", new ThumbnailProvider);
        w->engine->load(QUrl("qrc:/Main.qml"));
        if (w->engine->rootObjects().isEmpty())
            return w;
        w->window = qobject_cast<QQuickWindow *>(w->engine->rootObjects().first());
        w->idle->setWindow(w->window);
        return w;
    }

    void close(std::unique_ptr<Window> &w) {
        if (w->window)
            w->window->close();
        w->backend->close();
        QCoreApplication::removeTranslator(w->translator.get());
        w->engine.reset();
        w.reset();
    }

    // The offscreen platform renders with Qt Quick's software path, which
    // can't draw a VideoOutput, so the frame on screen is painted where the
    // picture is and the window, with a clear background, over it.
    void shot(Window *w, const QString &name) {
        const QString directory = qEnvironmentVariable("OMAVIEW_SHOTS");
        if (directory.isEmpty())
            return;
        QDir().mkpath(directory);
        const QColor background = w->window->color();
        auto *backgroundItem = w->window->property("background").value<QQuickItem *>();
        auto *video = w->window->findChild<QQuickItem *>("video");
        // The software renderer draws the VideoOutput as a white box, so it
        // is left out of the grab and its frame painted beneath instead.
        const bool videoShown = video && video->isVisible();
        if (videoShown)
            video->setVisible(false);
        w->window->setColor(Qt::transparent);
        backgroundItem->setVisible(false);
        QImage ui = w->window->grabWindow();
        backgroundItem->setVisible(true);
        if (videoShown)
            video->setVisible(true);
        w->window->setColor(background);
        QImage image(ui.size(), QImage::Format_ARGB32_Premultiplied);
        image.fill(background);
        QPainter painter(&image);
        QImage frame = w->backend->currentFrame().isValid() ? QVideoFrame(w->backend->currentFrame()).toImage() : QImage();
        if (video && !frame.isNull() && w->backend->hasVideo()) {
            const QRectF picture = video->property("contentRect").toRectF();
            const qreal ratio = qreal(ui.width()) / w->window->width();
            painter.drawImage(QRectF(picture.topLeft() * ratio, picture.size() * ratio), frame);
        }
        painter.drawImage(0, 0, ui);
        painter.end();
        image.save(directory + "/" + name + ".png");
    }

    template <typename T>
    T *find(Window *w, const char *name) {
        return w->window->findChild<T *>(name);
    }

    // Through the items as drawn, which reaches a view's delegates.
    static QQuickItem *findItem(QQuickItem *item, const QString &name) {
        if (item->objectName() == name)
            return item;
        for (QQuickItem *child : item->childItems())
            if (QQuickItem *found = findItem(child, name))
                return found;
        return nullptr;
    }

private slots:
    void initTestCase() {
        QQuickStyle::setStyle("Material");
        // So a screenshot's window can be grabbed with a clear background.
        QQuickWindow::setDefaultAlphaBuffer(true);
        QVERIFY(m_dir.isValid());
        // Caches and state go to a temp home, and nothing here may reach the
        // desktop's clipboard.
        qputenv("XDG_CACHE_HOME", m_dir.filePath("cache").toUtf8());
        qputenv("XDG_STATE_HOME", m_dir.filePath("state").toUtf8());
        qunsetenv("WAYLAND_DISPLAY");
        // A fresh cache home makes fontconfig read every font the first time
        // text is drawn, which takes seconds; it happens here, once, rather
        // than in the middle of a test that has the controls up.
        QImage warm(16, 16, QImage::Format_ARGB32);
        QPainter(&warm).drawText(0, 12, "x");
        QVERIFY(makeClip(m_dir.path(), "a-coast.mkv", 8));
        QVERIFY(makeClip(m_dir.path(), "b-pines.mkv", 3));
        m_clip = m_dir.filePath("a-coast.mkv");
        m_second = m_dir.filePath("b-pines.mkv");
    }

    void emptyWindowSaysWhatToDo() {
        auto w = open(m_dir.filePath("empty"));
        QVERIFY(w->window);
        QVERIFY(QTest::qWaitForWindowExposed(w->window));
        // Nothing to play starts no player.
        QVERIFY(!w->backend->playerReady());
        QTest::keyClick(w->window, Qt::Key_O, Qt::ControlModifier);
        QCOMPARE(w->picker->opens, 1);
        shot(w.get(), "0-empty");
        QVERIFY2(w->warnings.isEmpty(), qPrintable(w->warnings.join('\n')));
        close(w);
    }

    void playsAndAnswersTheKeyboard() {
        auto w = open(m_dir.filePath("play"));
        QVERIFY(w->window);
        w->window->resize(960, 540);
        QVERIFY(QTest::qWaitForWindowExposed(w->window));
        w->window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(w->window));

        w->backend->open({m_clip});
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->playing(), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->position() > 300, 10000);
        QVERIFY(w->backend->hasVideo());
        QCOMPARE(w->backend->videoSize(), QSize(640, 360));
        QCOMPARE(w->backend->playlistCount(), 2);
        QTRY_COMPARE(w->backend->chapters().size(), 2);
        QTRY_COMPARE(w->backend->audioLabel(), QString("English · stereo"));
        // The scrub previews follow, once the player knows enough about the file.
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->previewCount() > 0, 30000);
        QVERIFY(w->backend->previewSource().toLocalFile().startsWith(m_dir.filePath("cache")));
        // English everywhere, so subtitles start off.
        QCOMPARE(w->backend->subtitleChoices(), 1);
        QCOMPARE(w->backend->subtitleLabel(), QString());

        QTest::keyClick(w->window, Qt::Key_Space);
        QTRY_VERIFY(!w->backend->playing());

        // Bare, the thin line runs along the bottom, but not fullscreen.
        w->window->setProperty("overlayShown", false);
        auto *line = find<QQuickItem>(w.get(), "progressLine");
        QTRY_VERIFY(line->isVisible());
        w->window->showFullScreen();
        QTRY_VERIFY(w->window->property("fullscreen").toBool());
        QVERIFY(!line->isVisible());
        w->window->showNormal();
        QTRY_VERIFY(line->isVisible());
        w->window->setProperty("overlayShown", true);

        // Speed and volume say what they became.
        auto *levelValue = find<QQuickItem>(w.get(), "levelValue");
        QTest::keyClick(w->window, Qt::Key_BracketRight);
        QCOMPARE(w->backend->rate(), 1.25);
        QCOMPARE(levelValue->property("text").toString(), QString("1.25×"));
        QTest::keyClick(w->window, Qt::Key_Backspace);
        QCOMPARE(w->backend->rate(), 1.0);
        const double volume = w->backend->volume();
        QTest::keyClick(w->window, Qt::Key_Down);
        QCOMPARE(w->backend->volume(), std::round((volume - 0.05) * 100) / 100);
        // Past the file's own level is a boost, as far as the maximum.
        w->backend->setVolume(9);
        QCOMPARE(w->backend->volume(), w->backend->maxVolume());
        w->backend->setVolume(volume);
        QTRY_COMPARE(find<QQuickItem>(w.get(), "levelOsd")->opacity(), 1.0);

        // Subtitles on with C, drawn by the window at their time.
        QTest::keyClick(w->window, Qt::Key_C);
        QCOMPARE(w->backend->subtitleLabel(), QString("English"));
        // Seeking into the middle of a line shows the line, once the track's
        // cues have been read out.
        w->backend->seek(1500);
        auto *subtitle = find<QQuickItem>(w.get(), "subtitle");
        QTRY_VERIFY_WITH_TIMEOUT(subtitle->property("text").toString().contains("driving"), 8000);
        w->backend->seek(4500);
        QTRY_COMPARE(subtitle->property("text").toString(), QString("Then we walked."));
        w->backend->seek(1500);
        shot(w.get(), "1-bare");

        // Seeking with the keys, and a tenth of the way with the digits.
        w->backend->seek(1000);
        QTest::keyClick(w->window, Qt::Key_Right);
        QCOMPARE(w->backend->position(), qint64(6000));
        QTest::keyClick(w->window, Qt::Key_3);
        QVERIFY(qAbs(w->backend->position() - w->backend->duration() * 3 / 10) < 100);
        QCOMPARE(w->backend->chapterTitle(), QString("Leaving the city"));
        QTest::keyClick(w->window, Qt::Key_PageDown);
        QCOMPARE(w->backend->position(), qint64(4000));
        QCOMPARE(w->backend->chapterTitle(), QString("The coast road"));

        // A frame step moves by the frame's own timestamps.
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->currentFrame().isValid(), 5000);
        QTest::qWait(300);
        const qint64 before = w->backend->position();
        QTest::keyClick(w->window, Qt::Key_Period);
        QVERIFY(w->backend->position() > before);
        QVERIFY2(w->backend->position() - before <= 60, qPrintable(QString::number(w->backend->position() - before)));
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->currentFrame().startTime() / 1000 >= before, 5000);
        const qint64 stepped = w->backend->position();
        QTest::keyClick(w->window, Qt::Key_Comma);
        QVERIFY(w->backend->position() < stepped);
        QVERIFY(stepped - w->backend->position() <= 60);

        // The controls show from the start; Esc puts them away, and Tab
        // brings them back.
        auto *overlay = find<QQuickItem>(w.get(), "overlay");
        QTRY_VERIFY(overlay->property("item").value<QQuickItem *>());
        QTRY_COMPARE(overlay->property("item").value<QQuickItem *>()->opacity(), 1.0);
        shot(w.get(), "2-overlay");
        // Its icons say what they are, and their key, under the pointer.
        auto *keysButton = findItem(w->window->contentItem(), "keysButton");
        QVERIFY(keysButton);
        QTest::mouseMove(w->window, keysButton->mapToScene(QPointF(keysButton->width() / 2, keysButton->height() / 2)).toPoint());
        QTRY_VERIFY_WITH_TIMEOUT([&] {
            for (QObject *tip : w->window->findChildren<QObject *>())
                if (tip->inherits("QQuickToolTipAttached") && tip->property("visible").toBool())
                    return tip->property("text").toString() == "Show or hide the shortcuts   ?";
            return false;
        }(), 3000);
        QTest::mouseMove(w->window, QPoint(5, w->window->height() / 2));
        QTest::keyClick(w->window, Qt::Key_Escape);
        QTRY_VERIFY(!overlay->property("item").value<QQuickItem *>());
        QTest::keyClick(w->window, Qt::Key_Tab);
        QTRY_VERIFY(overlay->property("item").value<QQuickItem *>());
        QTest::keyClick(w->window, Qt::Key_Tab);
        QTRY_VERIFY(!overlay->property("item").value<QQuickItem *>());

        // I and ? open their cards; Escape closes them.
        auto *info = w->window->findChild<QObject *>("info");
        QTest::keyClick(w->window, Qt::Key_I);
        QTRY_VERIFY(info->property("opened").toBool());
        shot(w.get(), "3-info");
        QTest::keyClick(w->window, Qt::Key_Escape);
        QTRY_VERIFY(!info->property("visible").toBool());
        // The key that opens a card closes it too, though the card holds the keys.
        QTest::keyClick(w->window, Qt::Key_I);
        QTRY_VERIFY(info->property("opened").toBool());
        QTest::keyClick(w->window, Qt::Key_I);
        QTRY_VERIFY(!info->property("visible").toBool());
        auto *help = w->window->findChild<QObject *>("help");
        QTest::keyClick(w->window, '?');
        QTRY_VERIFY(help->property("opened").toBool());
        shot(w.get(), "4-help");
        QTest::keyClick(w->window, Qt::Key_Escape);
        QTRY_VERIFY(!help->property("visible").toBool());
        QTest::keyClick(w->window, '?');
        QTRY_VERIFY(help->property("opened").toBool());
        QTest::keyClick(w->window, '?');
        QTRY_VERIFY(!help->property("visible").toBool());

        // Save frame asks the picker, suggesting a name with the time.
        QTest::keyClick(w->window, Qt::Key_S, Qt::ControlModifier);
        QVERIFY2(w->picker->suggested.fileName().startsWith("a-coast-00-0"),
                 qPrintable(w->picker->suggested.toString()));
        QVERIFY(w->picker->suggested.fileName().endsWith(".png"));

        QVERIFY2(w->warnings.isEmpty(), qPrintable(w->warnings.join('\n')));
        close(w);
    }

    void endOffersTheNextFile() {
        auto w = open(m_dir.filePath("end"));
        QVERIFY(w->window);
        QVERIFY(QTest::qWaitForWindowExposed(w->window));
        w->window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(w->window));
        // A folder opens on its grid with nothing playing, not even heard,
        // until a tile is picked.
        w->backend->open({QFileInfo(m_clip).absolutePath()});
        QTRY_VERIFY(w->window->property("gridShown").toBool());
        // At the size of its tiles: as many 240px ones across as fit in 80% of
        // the 800px test screen, two, and as tall as its two files' one row.
        QTRY_COMPARE(w->window->size(), QSize(8 + 2 * 248, 16 + 188));
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->playerReady(), 10000);
        QTest::qWait(1000);
        QVERIFY(!w->backend->playing());
        QTest::keyClick(w->window, Qt::Key_Return);
        QTRY_VERIFY(!w->window->property("gridShown").toBool());
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->playing(), 10000);
        w->backend->open({m_clip});
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->playing(), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->seekable(), 10000);
        // In the grid, the video picked flips through frames from across it,
        // with nothing playing.
        QTest::keyClick(w->window, Qt::Key_M, Qt::ControlModifier);
        QVERIFY(!w->backend->playing());
        QTRY_VERIFY_WITH_TIMEOUT(findItem(w->window->contentItem(), "gridPreview"), 5000);
        auto *preview = findItem(w->window->contentItem(), "gridPreview");
        QTRY_VERIFY_WITH_TIMEOUT(preview->property("frame").toInt() >= 2, 20000);
        QTest::keyClick(w->window, Qt::Key_Escape);
        QTRY_VERIFY(!w->window->property("gridShown").toBool());
        // The controls' grid button opens it too, clicked once the controls
        // are laid out in the window's new shape, so the click lands on it.
        QTRY_VERIFY(w->window->property("sized").toBool() && w->window->property("reshaped").toBool());
        QQuickItem *gridButton = nullptr;
        QTRY_VERIFY([&] {
            std::function<QQuickItem *(QQuickItem *)> visible = [&](QQuickItem *item) -> QQuickItem * {
                if (item->objectName() == "gridButton" && item->isVisible())
                    return item;
                for (QQuickItem *child : item->childItems())
                    if (QQuickItem *found = visible(child))
                        return found;
                return nullptr;
            };
            gridButton = visible(w->window->contentItem());
            if (!gridButton || w->window->contentItem()->width() != w->window->width())
                return false;
            const QPointF middle = gridButton->mapToScene(QPointF(gridButton->width() / 2, gridButton->height() / 2));
            return QRectF(QPointF(), w->window->size()).contains(middle);
        }());
        QTest::mouseClick(w->window, Qt::LeftButton, {},
                          gridButton->mapToScene(QPointF(gridButton->width() / 2, gridButton->height() / 2)).toPoint());
        QTRY_VERIFY(w->window->property("gridShown").toBool());
        QTest::keyClick(w->window, Qt::Key_Escape);
        QTRY_VERIFY(!w->window->property("gridShown").toBool());
        w->backend->play();
        // Looping, the end goes back to the start rather than stopping.
        QTest::keyClick(w->window, Qt::Key_R);
        QVERIFY(w->backend->looping());
        w->backend->seek(w->backend->duration() - 300);
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->position() < 1000, 10000);
        QVERIFY(!w->backend->ended());
        QVERIFY(w->backend->playing());
        QTest::keyClick(w->window, Qt::Key_R);
        QVERIFY(!w->backend->looping());
        w->backend->seek(w->backend->duration() - 300);
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->ended(), 10000);
        QCOMPARE(w->backend->nextName(), QString("b-pines.mkv"));
        // The last frame stays rather than going black.
        QVERIFY(w->backend->currentFrame().isValid());
        shot(w.get(), "5-end");
        QTest::keyClick(w->window, Qt::Key_Return);
        QTRY_COMPARE(w->backend->fileName(), QString("b-pines.mkv"));
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->playing(), 10000);
        // A second video is still a video: the picture, not the song view,
        // and the screen held on while it plays and only then.
        QTRY_VERIFY(w->backend->currentFrame().isValid());
        QVERIFY(w->backend->hasVideo());
        QVERIFY(w->idle->active());
        w->backend->pause();
        QVERIFY(!w->idle->active());
        w->backend->play();
        QCOMPARE(w->backend->nextName(), QString());
        // N past the last file stays on it, without a word.
        QTest::keyClick(w->window, Qt::Key_N);
        QCOMPARE(w->backend->fileName(), QString("b-pines.mkv"));
        QVERIFY2(w->warnings.isEmpty(), qPrintable(w->warnings.join('\n')));
        close(w);
    }

    void aSongShowsItsCover() {
        QVERIFY(QProcess::execute("ffmpeg", {"-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=300x300:duration=1",
                                             "-frames:v", "1", m_dir.filePath("cover.png")}) == 0);
        const QString song = m_dir.filePath("song.mp3");
        QVERIFY(QProcess::execute("ffmpeg", {"-v", "error", "-y", "-f", "lavfi", "-i", "sine=duration=4", "-i",
                                             m_dir.filePath("cover.png"), "-map", "0:a", "-map", "1:v", "-c:a",
                                             "libmp3lame", "-c:v", "mjpeg", "-disposition:v", "attached_pic",
                                             "-metadata", "title=Low Tide", "-metadata", "artist=The Pines", song}) == 0);
        auto w = open(m_dir.filePath("song"));
        QVERIFY(w->window);
        QVERIFY(QTest::qWaitForWindowExposed(w->window));
        w->backend->open({song});
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->playing(), 10000);
        QTRY_COMPARE(w->backend->title(), QString("Low Tide"));
        QTRY_COMPARE(w->backend->artist(), QString("The Pines"));
        QTRY_VERIFY(w->backend->coverArt().startsWith("data:image/jpeg;base64,"));
        QVERIFY(!w->backend->hasVideo());
        // The screen is held on only for a picture, and a song gets a square.
        QVERIFY(!w->idle->active());
        QTRY_COMPARE(w->window->width(), w->window->height());
        shot(w.get(), "7-song");
        QVERIFY2(w->warnings.isEmpty(), qPrintable(w->warnings.join('\n')));
        close(w);
    }

    void aLightThemeKeepsThePictureDark() {
        const QString state = m_dir.filePath("light");
        QVERIFY(QDir().mkpath(state + "/theme"));
        QVERIFY(write(state + "/theme/colors.toml", "accent = \"#1e66f5\"\nbackground = \"#eff1f5\"\n"
                                                   "foreground = \"#4c4f69\"\nmuted = \"#8c8fa1\"\n"));
        auto w = open(state);
        QVERIFY(w->window);
        QVERIFY(w->theme->light());
        w->window->resize(960, 540);
        QVERIFY(QTest::qWaitForWindowExposed(w->window));
        w->window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(w->window));
        w->backend->open({m_clip});
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->playing(), 10000);
        QCOMPARE(w->window->color(), QColor("black"));
        QTest::keyClick(w->window, Qt::Key_Up);
        auto *levelValue = find<QQuickItem>(w.get(), "levelValue");
        QCOMPARE(levelValue->property("color").value<QColor>(), QColor("#1e66f5"));
        // Paused once a frame is up, so the shot has a picture.
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->currentFrame().isValid(), 10000);
        w->backend->pause();
        QTRY_COMPARE(find<QQuickItem>(w.get(), "levelOsd")->opacity(), 1.0);
        shot(w.get(), "8-light");
        QVERIFY2(w->warnings.isEmpty(), qPrintable(w->warnings.join('\n')));
        close(w);
    }

    void picturesStepZoomAndTurn() {
        // A folder of its own, as a camera's: two photos, an animation and a
        // drawing with a see-through background.
        const QString photos = m_dir.filePath("photos");
        QVERIFY(QDir().mkpath(photos));
        auto still = [&](const QString &source, const QString &name) {
            return QProcess::execute("ffmpeg", {"-v", "error", "-y", "-f", "lavfi", "-i", source, "-frames:v", "1",
                                                photos + "/" + name}) == 0;
        };
        QVERIFY(still("testsrc2=size=1600x900", "1-harbour.png"));
        QVERIFY(still("mandelbrot=size=900x1200", "2-shell.jpg"));
        QVERIFY(QProcess::execute("ffmpeg", {"-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=120x90:rate=5:duration=1",
                                             photos + "/3-blink.gif"}) == 0);
        QVERIFY(write(photos + "/4-mark.svg", "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='32'>"
                                              "<circle cx='16' cy='16' r='14' fill='#e5c07b'/></svg>"));

        auto w = open(m_dir.filePath("pictures"));
        QVERIFY(w->window);
        QVERIFY(QTest::qWaitForWindowExposed(w->window));
        w->window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(w->window));
        // Bare, without the controls, so the corner shows.
        w->window->setProperty("overlayShown", false);
        w->backend->open({photos + "/1-harbour.png"});
        auto *view = find<QQuickItem>(w.get(), "pictureView");
        QTRY_VERIFY_WITH_TIMEOUT(view->property("ready").toBool(), 10000);
        QTRY_COMPARE(w->backend->playlistCount(), 4);
        // The corner says where it is in the folder, and its name.
        QTRY_COMPARE(find<QQuickItem>(w.get(), "cornerOsd")->opacity(), 1.0);
        QTRY_COMPARE(find<QQuickItem>(w.get(), "cornerStatus")->property("text").toString(), QString("1 of 4"));
        // A picture never starts the player, and the window takes its shape.
        QVERIFY(!w->backend->playerReady());
        QTRY_COMPARE(qRound(w->window->width() * 900.0 / w->window->height()), 1600);
        QVERIFY(view->property("fitted").toBool());
        QVERIFY(!w->idle->active());
        shot(w.get(), "10-picture");

        // Zoomed in, the arrows move it about rather than step.
        QTest::keyClick(w->window, Qt::Key_Plus);
        QVERIFY(!view->property("fitted").toBool());
        QVERIFY(view->property("pannable").toBool());
        QTest::keyClick(w->window, Qt::Key_Left);
        QVERIFY(view->property("panX").toDouble() > 0);
        QCOMPARE(w->backend->playlistIndex(), 0);
        QTest::keyClick(w->window, Qt::Key_1);
        QCOMPARE(view->property("ratio").toDouble(), 1.0);
        QTest::keyClick(w->window, Qt::Key_0);
        QVERIFY(view->property("fitted").toBool());
        QCOMPARE(view->property("panX").toDouble(), 0.0);

        // Fitted, they step; a turn swaps its shape and the next file is upright.
        QTest::keyClick(w->window, Qt::Key_Right);
        QCOMPARE(w->backend->fileName(), QString("2-shell.jpg"));
        QTRY_COMPARE(view->property("naturalWidth").toDouble(), 900.0);
        // The window takes each picture's shape, a tall one after a wide one.
        QTRY_COMPARE(qRound(w->window->height() * 900.0 / w->window->width()), 1200);
        QTest::keyClick(w->window, Qt::Key_R);
        QCOMPARE(w->backend->rotation(), 90);
        QCOMPARE(view->property("turnedWidth").toDouble(), 1200.0);
        QTRY_COMPARE(qRound(w->window->width() * 900.0 / w->window->height()), 1200);
        QTest::keyClick(w->window, Qt::Key_Tab);
        QTRY_VERIFY(find<QQuickItem>(w.get(), "overlay")->property("item").value<QQuickItem *>());
        shot(w.get(), "11-picture-overlay");
        QTest::keyClick(w->window, Qt::Key_Escape);

        // An animation pauses on Space; End and Home go to the last and first.
        QTest::keyClick(w->window, Qt::Key_End);
        QCOMPARE(w->backend->fileName(), QString("4-mark.svg"));
        QCOMPARE(w->backend->rotation(), 0);
        QTRY_VERIFY(w->backend->vector() && w->backend->transparent());
        QTRY_VERIFY(view->property("ready").toBool());
        QTest::keyClick(w->window, Qt::Key_Left);
        QCOMPARE(w->backend->fileName(), QString("3-blink.gif"));
        QTRY_VERIFY(w->backend->animated());
        QTest::keyClick(w->window, Qt::Key_Space);
        QVERIFY(view->property("paused").toBool());
        QTest::keyClick(w->window, Qt::Key_Home);
        QCOMPARE(w->backend->fileName(), QString("1-harbour.png"));
        QVERIFY(!view->property("paused").toBool());

        // What comes of something asked for shows a moment in the middle.
        QTest::keyClick(w->window, Qt::Key_C, Qt::ControlModifier);
        QTRY_COMPARE(findItem(w->window->contentItem(), "levelMessage")->property("text").toString(),
                     QString("Copied the picture"));

        // Ctrl+M: every file in the folder, the one shown picked; the arrows
        // move, Ctrl++ makes the tiles bigger, and Enter opens one.
        QTest::keyClick(w->window, Qt::Key_M, Qt::ControlModifier);
        QTRY_VERIFY(find<QQuickItem>(w.get(), "gridView"));
        auto *grid = find<QQuickItem>(w.get(), "gridView");
        QTRY_COMPARE(grid->property("count").toInt(), 4);
        QCOMPARE(grid->property("currentIndex").toInt(), 0);
        const double tiles = w->window->property("gridTileSize").toDouble();
        QTest::keyClick(w->window, Qt::Key_Equal, Qt::ControlModifier);
        QVERIFY(w->window->property("gridTileSize").toDouble() > tiles);
        QTest::keyClick(w->window, Qt::Key_Right);
        QCOMPARE(grid->property("currentIndex").toInt(), 1);
        // Its keys are the grid's: N doesn't step the file behind it.
        QTest::keyClick(w->window, Qt::Key_N);
        QCOMPARE(w->backend->fileName(), QString("1-harbour.png"));
        shot(w.get(), "13-grid");
        QTest::keyClick(w->window, Qt::Key_Return);
        QTRY_VERIFY(!w->window->property("gridShown").toBool());
        QTRY_COMPARE(w->backend->fileName(), QString("2-shell.jpg"));
        QTest::keyClick(w->window, Qt::Key_M, Qt::ControlModifier);
        QTRY_VERIFY(w->window->property("gridShown").toBool());
        // A file opened from elsewhere puts the grid away to show it.
        w->backend->open({photos + "/4-mark.svg"});
        QTRY_VERIFY(!w->window->property("gridShown").toBool());
        QTRY_COMPARE(w->backend->fileName(), QString("4-mark.svg"));
        w->backend->open({photos + "/2-shell.jpg"});
        QTest::keyClick(w->window, Qt::Key_M, Qt::ControlModifier);
        QTRY_VERIFY(w->window->property("gridShown").toBool());
        QTest::keyClick(w->window, Qt::Key_Escape);
        QTRY_VERIFY(!w->window->property("gridShown").toBool());
        QTest::keyClick(w->window, Qt::Key_Home);

        // The ? overlay lists a picture's keys first.
        QTest::keyClick(w->window, Qt::Key_F1);
        auto *help = find<QObject>(w.get(), "help");
        QTRY_VERIFY(help->property("opened").toBool());
        QCOMPARE(w->window->property("shortcutList").toList().value(1).toMap().value("action").toString(),
                 QString("Previous or next file"));
        shot(w.get(), "12-picture-keys");
        QVERIFY2(w->warnings.isEmpty(), qPrintable(w->warnings.join('\n')));
        close(w);
    }

    void aFolderOfOneFitsItsTile() {
        const QString lone = m_dir.filePath("one");
        QVERIFY(QDir().mkpath(lone));
        QVERIFY(QProcess::execute("ffmpeg", {"-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=640x480",
                                             "-frames:v", "1", lone + "/only.png"}) == 0);
        auto w = open(m_dir.filePath("one-state"));
        QVERIFY(w->window);
        QVERIFY(QTest::qWaitForWindowExposed(w->window));
        w->backend->open({lone});
        QTRY_VERIFY(w->window->property("gridShown").toBool());
        // Held to the window's least width, the tile stretches to 304 across,
        // and the window is as tall as it then is.
        QTRY_COMPARE(w->window->size(), QSize(320, 16 + 228 + 8));
        close(w);
    }

    void aPictureThatWontShowSaysWhy() {
        auto w = open(m_dir.filePath("broken-picture"));
        QVERIFY(w->window);
        QVERIFY(QTest::qWaitForWindowExposed(w->window));
        const QString broken = m_dir.filePath("broken.png");
        QVERIFY(write(broken, "this is not a picture"));
        w->backend->open({broken});
        QTRY_COMPARE(w->backend->error(), QString("Its format isn't one Omaview can show."));
        QTRY_VERIFY(find<QQuickItem>(w.get(), "error")->isVisible());
        QVERIFY(!w->backend->playerReady());
        QVERIFY2(w->warnings.isEmpty(), qPrintable(w->warnings.join('\n')));
        close(w);
    }

    // With OMAVIEW_README_SHOTS set to a directory, shoots the README's
    // pictures in the real window: a made-up fjord, at a time of day each,
    // with a camera's EXIF, and two films made from it. Run it with
    // QT_SCALE_FACTOR=2 for shots at twice the size.
    void readmeScreenshots() {
        const QString out = qEnvironmentVariable("OMAVIEW_README_SHOTS");
        if (out.isEmpty())
            QSKIP("Set OMAVIEW_README_SHOTS to a directory to shoot the README's pictures");
        qputenv("OMAVIEW_SHOTS", out.toUtf8());
        using namespace fixtures;
        const QString folder = m_dir.filePath("Fjord");
        QVERIFY(QDir().mkpath(folder));
        const QList<int> times{0, 3, 2, 1, 4, 5, 0};
        for (int i = 0; i < times.size(); ++i) {
            const QByteArray taken = QByteArray("2026:09:21 ") + QByteArray::number(19 + i % 3) + ":42:0" + QByteArray::number(i);
            QVERIFY(write(folder + QString("/IMG_%1.jpg").arg(2041 + i),
                          jpegWithExif(fjord(QSize(3000, 2000), times[i], i * 0.37 - (i > 5 ? 0.6 : 0)),
                                       {ascii(0x010F, "FUJIFILM"), ascii(0x0110, "X-T5"), shortTag(0x0112, 1)},
                                       {rational(0x829A, 1, 125), rational(0x829D, 56, 10), shortTag(0x8827, 320),
                                        ascii(0x9003, taken), rational(0x920A, 23, 1), shortTag(0xA405, 35),
                                        ascii(0xA434, "XF23mmF1.4 R LM WR")})));
        }
        // A film drifting slowly in over the water, with a line said over it.
        auto film = [&](const QString &name, int time, const QByteArray &title) {
            fjord(QSize(3840, 2160), time, 0.2).save(m_dir.filePath("still.png"));
            write(m_dir.filePath("film.srt"), "1\n00:00:00,500 --> 00:00:11,500\nThe ferry only runs\nwhile the light holds.\n");
            write(m_dir.filePath("film.txt"), ";FFMETADATA1\ntitle=" + title + "\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=6000\n"
                                              "title=The landing\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=6000\nEND=12000\ntitle=Out on the water\n");
            QProcess ffmpeg;
            ffmpeg.setWorkingDirectory(m_dir.path());
            ffmpeg.start("ffmpeg", {"-v", "error", "-y", "-loop", "1", "-i", "still.png", "-f", "lavfi", "-i",
                                    "sine=frequency=220:duration=12", "-i", "film.srt", "-i", "film.txt", "-filter_complex",
                                    "[0:v]zoompan=z='1+0.0004*on':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=300:s=1920x1080:fps=25[v]",
                                    "-map", "[v]", "-map", "1:a", "-map", "2:s", "-map_metadata", "3", "-map_chapters", "3",
                                    "-t", "12", "-c:v", "libx264", "-preset", "veryfast", "-g", "25", "-pix_fmt", "yuv420p",
                                    "-c:a", "aac", "-c:s", "srt", "-metadata:s:a:0", "language=eng",
                                    "-metadata:s:s:0", "language=eng", folder + "/" + name});
            return ffmpeg.waitForFinished(120000) && ffmpeg.exitCode() == 0;
        };
        QVERIFY(film("Crossing the fjord.mkv", 1, "Crossing the Fjord"));
        QVERIFY(film("Evening ferry.mkv", 0, "Evening Ferry"));

        auto w = open(m_dir.filePath("readme"));
        QVERIFY(w->window);
        w->window->resize(1440, 960);
        QVERIFY(QTest::qWaitForWindowExposed(w->window));
        w->window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(w->window));

        // A photo with its controls, and its card.
        w->backend->open({folder + "/IMG_2041.jpg"});
        auto *view = find<QQuickItem>(w.get(), "pictureView");
        QTRY_VERIFY_WITH_TIMEOUT(view->property("ready").toBool(), 10000);
        QTRY_COMPARE(w->backend->playlistCount(), 9);
        QTest::qWait(400);
        shot(w.get(), "picture");
        QTest::keyClick(w->window, Qt::Key_I);
        QTRY_VERIFY(find<QObject>(w.get(), "info")->property("opened").toBool());
        QTest::qWait(400);
        shot(w.get(), "picture-info");
        QTest::keyClick(w->window, Qt::Key_I);
        QTRY_VERIFY(!find<QObject>(w.get(), "info")->property("visible").toBool());

        // The folder as a grid, the first film picked and flipping through.
        QTest::keyClick(w->window, Qt::Key_M, Qt::ControlModifier);
        QTRY_VERIFY(w->window->property("gridShown").toBool());
        for (int i = 0; i < 3; ++i)
            QTest::keyClick(w->window, Qt::Key_Equal, Qt::ControlModifier);
        QTest::keyClick(w->window, Qt::Key_Home);
        QTRY_VERIFY_WITH_TIMEOUT(findItem(w->window->contentItem(), "gridPreview"), 10000);
        auto *preview = findItem(w->window->contentItem(), "gridPreview");
        QTRY_VERIFY_WITH_TIMEOUT(preview->property("frame").toInt() >= 4, 20000);
        QTest::qWait(1500);
        shot(w.get(), "grid");
        QTest::keyClick(w->window, Qt::Key_Escape);
        QTRY_VERIFY(!w->window->property("gridShown").toBool());

        close(w);

        // A film with its controls, its line on, and then bare, in a window
        // of its own: one resized after it shows loses its alpha, which the
        // shots need to paint the frame beneath.
        w = open(m_dir.filePath("readme-film"));
        QVERIFY(w->window);
        w->window->resize(1440, 810);
        QVERIFY(QTest::qWaitForWindowExposed(w->window));
        w->window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(w->window));
        w->backend->open({folder + "/Crossing the fjord.mkv"});
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->playing(), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->previewCount() > 0, 30000);
        QTest::keyClick(w->window, Qt::Key_C);
        w->backend->seek(4200);
        QTRY_VERIFY_WITH_TIMEOUT(!find<QQuickItem>(w.get(), "subtitle")->property("text").toString().isEmpty(), 8000);
        w->backend->pause();
        QTRY_VERIFY_WITH_TIMEOUT(w->backend->currentFrame().isValid(), 5000);
        QTest::qWait(500);
        shot(w.get(), "overlay");
        QTest::keyClick(w->window, Qt::Key_Tab);
        w->backend->play();
        QTest::qWait(2600);
        w->backend->pause();
        QTest::qWait(300);
        shot(w.get(), "bare");
        close(w);
    }

    void aFileThatWontPlaySaysWhy() {
        auto w = open(m_dir.filePath("broken"));
        QVERIFY(w->window);
        QVERIFY(QTest::qWaitForWindowExposed(w->window));
        const QString broken = m_dir.filePath("broken.mkv");
        QVERIFY(write(broken, "this is not a video"));
        w->backend->open({broken});
        QTRY_VERIFY_WITH_TIMEOUT(!w->backend->error().isEmpty(), 10000);
        auto *error = find<QQuickItem>(w.get(), "error");
        QTRY_VERIFY(error->isVisible());
        shot(w.get(), "6-error");
        QVERIFY2(w->warnings.isEmpty(), qPrintable(w->warnings.join('\n')));
        close(w);
    }
};

QTEST_MAIN(UiTests)
#include "ui_tests.moc"

