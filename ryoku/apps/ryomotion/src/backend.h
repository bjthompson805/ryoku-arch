#pragma once

// Backend: the bridge from QML to the `ryomotion` shell tool + ffprobe. Plain
// QtQuick has no process type, so record/export/graph/probe run here via
// QProcess. `requestGraph` returns the mpv lavfi-complex the live preview feeds
// its MpvItem; `exportVideo` runs the ffmpeg render (same graph engine).
#include <QObject>
#include <QtQml/qqmlregistration.h>
#include <QProcess>
#include <QString>
#include <QStringList>

class Backend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool recording READ recording NOTIFY recordingChanged)
    Q_PROPERTY(bool rendering READ rendering NOTIFY renderingChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    bool recording() const { return m_recording; }
    bool rendering() const { return m_rendering; }

    Q_INVOKABLE void probe(const QString &path);                 // -> probed()
    Q_INVOKABLE QString graph(const QString &projJson);          // sync: mpv lavfi-complex
    Q_INVOKABLE void exportVideo(const QString &projJson, const QString &outPath);
    Q_INVOKABLE void record(bool region);
    Q_INVOKABLE void stopRecord();
    Q_INVOKABLE QString videosDir() const;
    Q_INVOKABLE QStringList listClips() const;                   // recent clips under ~/Videos
    Q_INVOKABLE QString basename(const QString &path) const;

Q_SIGNALS:
    void probed(double durationMs, bool hasCursor);
    void recordingChanged();
    void renderingChanged();
    void recorded(const QString &projPath);
    void exportDone(bool ok, const QString &path);

private:
    QString runSync(const QString &program, const QStringList &args, int timeoutMs = 8000, const QString &jsonArgFile = {});
    QString writeTemp(const QString &content, const QString &name) const;

    bool m_recording = false;
    bool m_rendering = false;
    QString m_recProj;
    QProcess *m_render = nullptr;
};
