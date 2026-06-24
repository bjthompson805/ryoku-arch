pragma ComponentBehavior: Bound
import QtQuick

/**
 * The animated sky backdrop: picks the right animation for the current weather
 * category and fills its parent. The designs drop one of these behind their
 * readout at whatever size they need; `animate` lets a still preview or an
 * inhibited desktop freeze it.
 */
Item {
    id: sky

    property string category: "clouds"
    property bool isDay: true
    property bool animate: true

    Loader {
        anchors.fill: parent
        sourceComponent: sky.pick()
    }

    function pick() {
        switch (sky.category) {
        case "clear": return clearC;
        case "rain":  return rainC;
        case "snow":  return snowC;
        case "storm": return stormC;
        case "fog":   return fogC;
        default:      return cloudsC;
        }
    }

    Component { id: clearC;  SkyClear  { isDay: sky.isDay; animate: sky.animate } }
    Component { id: cloudsC; SkyClouds { isDay: sky.isDay; animate: sky.animate } }
    Component { id: rainC;   SkyRain   { animate: sky.animate } }
    Component { id: snowC;   SkySnow   { animate: sky.animate } }
    Component { id: stormC;  SkyStorm  { animate: sky.animate } }
    Component { id: fogC;    SkyFog    { animate: sky.animate } }
}
