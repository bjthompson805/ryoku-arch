#include "mpvitem.h"

#include <clocale>

#include <QGuiApplication>
#include <QOpenGLContext>
#include <QtOpenGL/QOpenGLFramebufferObject>
#include <QtQuick/QQuickWindow>
#include <QMetaObject>

#if __has_include(<QtGui/qguiapplication_platform.h>)
#include <QtGui/qguiapplication_platform.h>
#endif

#include <mpv/client.h>
#include <mpv/render_gl.h>

namespace {
void *get_proc_address_mpv(void *ctx, const char *name)
{
    Q_UNUSED(ctx)
    QOpenGLContext *glctx = QOpenGLContext::currentContext();
    if (!glctx)
        return nullptr;
    return reinterpret_cast<void *>(glctx->getProcAddress(QByteArray(name)));
}
}

// ---- renderer (runs on the scene-graph render thread) ----------------------
class MpvItemRenderer : public QQuickFramebufferObject::Renderer
{
    MpvItem *m_item;

public:
    explicit MpvItemRenderer(MpvItem *item) : m_item(item) {}

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        if (!m_item->m_mpvGl) {
            mpv_opengl_init_params glInit{get_proc_address_mpv, nullptr};
            int advanced = 1;
            mpv_render_param display{MPV_RENDER_PARAM_INVALID, nullptr};
#if __has_include(<QtGui/qguiapplication_platform.h>)
            if (QGuiApplication::platformName().contains(QStringLiteral("wayland"))) {
                if (auto *wl = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>()) {
                    display.type = MPV_RENDER_PARAM_WL_DISPLAY;
                    display.data = wl->display();
                }
            }
#endif
            mpv_render_param params[]{
                {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
                {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInit},
                {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced},
                display,
                {MPV_RENDER_PARAM_INVALID, nullptr}};
            if (mpv_render_context_create(&m_item->m_mpvGl, m_item->m_mpv, params) >= 0)
                mpv_render_context_set_update_callback(m_item->m_mpvGl, MpvItem::onRenderUpdate, m_item);
        }
        return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
    }

    void render() override
    {
        if (!m_item->m_mpvGl)
            return;
        QOpenGLFramebufferObject *fbo = framebufferObject();
        mpv_opengl_fbo mpfbo{static_cast<int>(fbo->handle()), fbo->width(), fbo->height(), 0};
        int flipY = 0;
        mpv_render_param params[]{
            {MPV_RENDER_PARAM_OPENGL_FBO, &mpfbo},
            {MPV_RENDER_PARAM_FLIP_Y, &flipY},
            {MPV_RENDER_PARAM_INVALID, nullptr}};
        if (m_item->window())
            m_item->window()->beginExternalCommands();
        mpv_render_context_render(m_item->m_mpvGl, params);
        if (m_item->window())
            m_item->window()->endExternalCommands();
    }
};

// ---- item (GUI thread) -----------------------------------------------------
MpvItem::MpvItem(QQuickItem *parent) : QQuickFramebufferObject(parent), m_mpv(mpv_create())
{
    if (!m_mpv)
        qFatal("could not create mpv context");

    mpv_set_option_string(m_mpv, "terminal", "no");
    mpv_set_option_string(m_mpv, "config", "no");
    mpv_set_option_string(m_mpv, "vo", "libmpv");
    mpv_set_option_string(m_mpv, "hwdec", "auto-safe");
    mpv_set_option_string(m_mpv, "keep-open", "yes");
    mpv_set_option_string(m_mpv, "idle", "yes");
    mpv_set_option_string(m_mpv, "pause", "yes");
    mpv_set_option_string(m_mpv, "loop-file", "inf");
    mpv_set_option_string(m_mpv, "audio", "no"); // preview is silent; export owns audio

    if (mpv_initialize(m_mpv) < 0)
        qFatal("could not initialize mpv context");

    mpv_observe_property(m_mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "pause", MPV_FORMAT_FLAG);

    mpv_set_wakeup_callback(m_mpv, MpvItem::onWakeup, this);
}

MpvItem::~MpvItem()
{
    if (m_mpvGl)
        mpv_render_context_free(m_mpvGl);
    if (m_mpv)
        mpv_terminate_destroy(m_mpv);
}

QQuickFramebufferObject::Renderer *MpvItem::createRenderer() const
{
    return new MpvItemRenderer(const_cast<MpvItem *>(this));
}

void MpvItem::onWakeup(void *ctx)
{
    QMetaObject::invokeMethod(static_cast<MpvItem *>(ctx), "onMpvEvents", Qt::QueuedConnection);
}

void MpvItem::onRenderUpdate(void *ctx)
{
    QMetaObject::invokeMethod(static_cast<MpvItem *>(ctx), "doUpdate", Qt::QueuedConnection);
}

void MpvItem::doUpdate()
{
    update();
}

void MpvItem::onMpvEvents()
{
    if (!m_mpv)
        return;
    while (true) {
        mpv_event *ev = mpv_wait_event(m_mpv, 0);
        if (ev->event_id == MPV_EVENT_NONE)
            break;
        switch (ev->event_id) {
        case MPV_EVENT_PROPERTY_CHANGE: {
            auto *prop = static_cast<mpv_event_property *>(ev->data);
            if (prop->format == MPV_FORMAT_DOUBLE && prop->data) {
                double v = *static_cast<double *>(prop->data);
                if (!qstrcmp(prop->name, "time-pos") && v != m_position) {
                    m_position = v;
                    Q_EMIT positionChanged();
                } else if (!qstrcmp(prop->name, "duration") && v != m_duration) {
                    m_duration = v;
                    Q_EMIT durationChanged();
                }
            } else if (prop->format == MPV_FORMAT_FLAG && prop->data) {
                bool f = *static_cast<int *>(prop->data);
                if (!qstrcmp(prop->name, "pause") && f != m_paused) {
                    m_paused = f;
                    Q_EMIT pausedChanged();
                }
            }
            break;
        }
        case MPV_EVENT_FILE_LOADED:
            if (!m_filters.isEmpty())
                mpv_set_property_string(m_mpv, "lavfi-complex", m_filters.toUtf8().constData());
            Q_EMIT fileLoaded();
            break;
        default:
            break;
        }
    }
}

void MpvItem::loadFile(const QUrl &url, const QStringList &externals)
{
    if (!m_mpv)
        return;
    QByteArray ext = externals.join(QStringLiteral(",")).toUtf8();
    mpv_set_option_string(m_mpv, "external-files", externals.isEmpty() ? "" : ext.constData());
    QByteArray path = (url.isLocalFile() ? url.toLocalFile() : url.toString()).toUtf8();
    const char *cmd[] = {"loadfile", path.constData(), nullptr};
    mpv_command(m_mpv, cmd);
}

void MpvItem::command(const QStringList &args)
{
    if (!m_mpv)
        return;
    QList<QByteArray> bytes;
    for (const QString &a : args)
        bytes.append(a.toUtf8());
    QVarLengthArray<const char *, 8> argv;
    for (const QByteArray &b : bytes)
        argv.append(b.constData());
    argv.append(nullptr);
    mpv_command(m_mpv, argv.data());
}

void MpvItem::setOption(const QString &name, const QString &value)
{
    if (m_mpv)
        mpv_set_option_string(m_mpv, name.toUtf8().constData(), value.toUtf8().constData());
}

void MpvItem::setProp(const QString &name, const QString &value)
{
    if (m_mpv)
        mpv_set_property_string(m_mpv, name.toUtf8().constData(), value.toUtf8().constData());
}

void MpvItem::setPosition(double pos)
{
    if (m_mpv)
        mpv_set_property_string(m_mpv, "time-pos", QByteArray::number(pos).constData());
}

void MpvItem::setPaused(bool p)
{
    if (m_mpv)
        mpv_set_property_string(m_mpv, "pause", p ? "yes" : "no");
}

void MpvItem::setSpeed(double s)
{
    if (s == m_speed)
        return;
    m_speed = s;
    if (m_mpv)
        mpv_set_property_string(m_mpv, "speed", QByteArray::number(s).constData());
    Q_EMIT speedChanged();
}

void MpvItem::setFilters(const QString &graph)
{
    if (graph == m_filters)
        return;
    m_filters = graph;
    if (m_mpv)
        mpv_set_property_string(m_mpv, "lavfi-complex", graph.isEmpty() ? "" : graph.toUtf8().constData());
    Q_EMIT filtersChanged();
}
