pragma Singleton
import QtQuick
import Quickshell.Io
import "../lib/weather.js" as Model

// pill's copy: the only root with an explicit-location setting (Config.
// weatherLocation, a typed city name), so the only one that needs geocoding
// on top of the shared WeatherCore implementation. resolveLocation()/writeLoc()
// override WeatherCore's defaults -- QML function overrides resolve on the
// final composed object, same mechanism launcher/Singletons/Spawn.qml already
// relies on for SpawnCore.
WeatherCore {
    id: root

    // resolve coords: an explicit Config.weatherLocation wins (geocoded), else the
    // cached coords for the same query, else the base's IP lookup. the cache is
    // keyed by the query, so a restart skips the round-trip only while the
    // location is unchanged.
    function resolveLocation() {
        var target = Config.weatherLocation.trim();
        var c = Model.parseJson(root._readLocFile());
        if (c && c.query === target && typeof c.lat === "number" && typeof c.lon === "number") {
            root.city = c.city || "";
            root.lat = c.lat;
            root.lon = c.lon;
            root.located = true;
            root.fetchWeather();
            return;
        }
        if (target.length > 0)
            geoProc.running = true;
        else
            root._geolocateByIp();
    }

    function writeLoc() {
        root._writeLocFile(JSON.stringify({ query: Config.weatherLocation, city: root.city, lat: root.lat, lon: root.lon }));
    }

    Connections {
        target: Config
        function onWeatherLocationChanged() { root.located = false; root.resolveLocation(); }
    }

    // geocode an explicit location via Open-Meteo's keyless geocoding API.
    Process {
        id: geoProc
        command: ["curl", "-s", "--max-time", "8",
            "https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name="
            + encodeURIComponent(Config.weatherLocation.trim())]
        stdout: StdioCollector {
            onStreamFinished: {
                var g = Model.parseGeo(Model.parseJson(this.text));
                if (g) {
                    root.city = g.city;
                    root.lat = g.lat;
                    root.lon = g.lon;
                    root.located = true;
                    root.writeLoc();
                    root.fetchWeather();
                }
            }
        }
    }
}
