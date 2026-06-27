pragma Singleton
import QtQuick
import Quickshell

/**
 * app/window icon resolution for Hyprland toplevels. a window class often
 * differs from its icon-theme name, so match the class to a desktop entry id
 * first, fall back to a direct icon-theme lookup. shared by every surface
 * that paints a window icon (minimized tray, ws switcher).
 */
Singleton {
    function iconFor(t) {
        var cls = (t && t.lastIpcObject && t.lastIpcObject.class) ? t.lastIpcObject.class
            : (t && t.wayland && t.wayland.appId ? t.wayland.appId : "");
        if (!cls)
            return "";
        var apps = DesktopEntries.applications.values;
        for (var i = 0; i < apps.length; i++) {
            var e = apps[i];
            if (e && e.id && e.id.toLowerCase() === cls.toLowerCase() && e.icon)
                return Quickshell.iconPath(e.icon, "application-x-executable");
        }
        return Quickshell.iconPath(cls, "application-x-executable");
    }
}
