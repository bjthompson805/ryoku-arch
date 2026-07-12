#pragma once

// MpvItem: a libmpv-backed video surface for Qt Quick. mpv decodes + renders
// into the scene-graph FBO (render API, OpenGL), and `filters` sets an ffmpeg
// lavfi-complex graph LIVE -- the same graph the exporter feeds ffmpeg, so the
// preview is exactly what you export. This is the whole point of the rebuild:
// one engine for preview and render.

#include <QtQuick/QQuickFramebufferObject>
#include <QtQml/qqmlregistration.h>
#include <QString>
#include <QStringList>
#include <QUrl>

struct mpv_handle;
struct mpv_render_context;

class MpvItem : public QQuickFramebufferObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(double position READ position WRITE setPosition NOTIFY positionChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(double speed READ speed WRITE setSpeed NOTIFY speedChanged)
    Q_PROPERTY(QString filters READ filters WRITE setFilters NOTIFY filtersChanged)

public:
    explicit MpvItem(QQuickItem *parent = nullptr);
    ~MpvItem() override;

    Renderer *createRenderer() const override;

    double duration() const { return m_duration; }
    double position() const { return m_position; }
    void setPosition(double pos);
    bool paused() const { return m_paused; }
    void setPaused(bool p);
    double speed() const { return m_speed; }
    void setSpeed(double s);
    QString filters() const { return m_filters; }
    void setFilters(const QString &graph);

    // Load a clip; extra source paths (background PNG, overlay clips) become
    // [vid2], [vid3], ... inside the lavfi graph via mpv external-files.
    Q_INVOKABLE void loadFile(const QUrl &url, const QStringList &externals = {});
    Q_INVOKABLE void command(const QStringList &args);
    Q_INVOKABLE void setOption(const QString &name, const QString &value);
    Q_INVOKABLE void setProp(const QString &name, const QString &value);

Q_SIGNALS:
    void durationChanged();
    void positionChanged();
    void pausedChanged();
    void speedChanged();
    void filtersChanged();
    void fileLoaded();

private Q_SLOTS:
    void doUpdate();
    void onMpvEvents();

private:
    static void onWakeup(void *ctx);
    static void onRenderUpdate(void *ctx);

    mpv_handle *m_mpv = nullptr;
    mpv_render_context *m_mpvGl = nullptr;
    double m_duration = 0;
    double m_position = 0;
    double m_speed = 1.0;
    bool m_paused = true;
    QString m_filters;

    friend class MpvItemRenderer;
};
