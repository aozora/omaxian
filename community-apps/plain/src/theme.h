#pragma once

#include <QColor>
#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QProcess>
#include <QTimer>

// The Omarchy palette, Hyprland's rounding and the desktop's text size,
// followed live. Syntax colors come from the palette, so it reads the whole
// colors.toml rather than only the accent, and the Material style flips with
// the theme's light or dark mode.
class Theme : public QObject {
    Q_OBJECT
    Q_PROPERTY(QColor accent READ accent NOTIFY changed)
    Q_PROPERTY(QColor accentForeground READ accentForeground NOTIFY changed)
    Q_PROPERTY(QColor background READ background NOTIFY changed)
    Q_PROPERTY(QColor darkBackground READ darkBackground NOTIFY changed)
    Q_PROPERTY(QColor foreground READ foreground NOTIFY changed)
    Q_PROPERTY(QColor brightForeground READ brightForeground NOTIFY changed)
    Q_PROPERTY(QColor secondaryForeground READ secondaryForeground NOTIFY changed)
    Q_PROPERTY(QColor red READ red NOTIFY changed)
    Q_PROPERTY(QColor green READ green NOTIFY changed)
    Q_PROPERTY(QColor yellow READ yellow NOTIFY changed)
    Q_PROPERTY(QColor blue READ blue NOTIFY changed)
    Q_PROPERTY(QColor magenta READ magenta NOTIFY changed)
    Q_PROPERTY(QColor orange READ orange NOTIFY changed)
    Q_PROPERTY(bool light READ light NOTIFY changed)
    Q_PROPERTY(int radius READ radius NOTIFY changed)
    // The desktop's text size in px: what the display panel's Text size slider
    // sets (12px there is the terminals' 9pt).
    Q_PROPERTY(int textSize READ textSize NOTIFY changed)

public:
    explicit Theme(const QString &currentDirectory = {}, QObject *parent = nullptr, const QString &hyprctl = {});
    ~Theme() override;

    QColor accent() const { return color("accent"); }
    QColor accentForeground() const;
    QColor background() const { return color("background"); }
    QColor darkBackground() const { return color("dark_background"); }
    QColor foreground() const { return color("foreground"); }
    QColor brightForeground() const { return color("bright_foreground"); }
    QColor secondaryForeground() const;
    QColor red() const { return color("red"); }
    QColor green() const { return color("green"); }
    QColor yellow() const { return color("yellow"); }
    QColor blue() const { return color("blue"); }
    QColor magenta() const { return color("magenta"); }
    QColor orange() const { return color("orange"); }
    bool light() const { return m_light; }
    int radius() const { return m_radius; }
    int textSize() const { return m_textSize; }

    // `base-size` under `[font]` in a shell.toml, or 0 when it isn't set.
    static int readBaseSize(const QString &path);

    struct Palette {
        QHash<QString, QColor> colors;
        bool light = false;
    };
    static Palette readPalette(const QString &path);

signals:
    void changed();

private:
    QColor color(const QString &key) const;
    void reload();
    void refreshRounding();

    QString m_directory;
    QString m_shellConfig;
    QHash<QString, QColor> m_colors;
    int m_textSize = 12;
    bool m_light = false;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QString m_hyprctl;
    int m_radius = 0;
    QProcess m_roundingProcess;
    QTimer m_roundingPoll, m_roundingTimeout;
};
