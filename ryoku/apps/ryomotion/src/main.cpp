#include <clocale>

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QSGRendererInterface>

// Ryoku Motion: native screen-demo editor. One engine (libmpv) previews the
// exact ffmpeg graph the exporter renders. QQuickFramebufferObject needs the
// OpenGL RHI backend, forced here before the app spins up.
int main(int argc, char *argv[])
{
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Ryoku Motion"));
    app.setDesktopFileName(QStringLiteral("ryomotion"));

    // libmpv requires the C locale for LC_NUMERIC.
    std::setlocale(LC_NUMERIC, "C");

    QQmlApplicationEngine engine;
    engine.loadFromModule("RyoMotion", "Main");
    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
