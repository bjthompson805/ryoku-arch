pragma Singleton
import QtQuick
import Quickshell
import "../lib/dispatch.js" as Dispatch

// Routes a search query to providers. A leading prefix char selects one provider;
// an unprefixed query fans across every default provider, merged by score and
// capped. Providers register themselves on load, so adding one never edits here.
Singleton {
    id: root

    property var registry: ({})   // id -> provider instance
    property var prefixes: ({})   // prefix char -> provider id
    function register(provider) {
        if (!provider || !provider.providerId)
            return;
        root.registry[provider.providerId] = provider;
        if (provider.prefix && provider.prefix.length === 1) {
            var p = root.prefixes;
            p[provider.prefix] = provider.providerId;
            root.prefixes = p;
        }
    }

    // The provider a prefixed query targets, or "" for the default fan-out.
    function route(text) {
        return Dispatch.routePrefix(text, root.prefixes);
    }

    // Merged, score-sorted, capped result rows for the current query.
    function results(text, limit) {
        var r = Dispatch.routePrefix(text, root.prefixes);
        var rows = [];
        if (r.provider) {
            var p = root.registry[r.provider];
            if (p)
                rows = p.query(r.query);
        } else {
            for (var id in root.registry) {
                var prov = root.registry[id];
                if (prov && prov.defaultProvider)
                    rows = rows.concat(prov.query(r.query));
            }
            rows.sort(function (a, b) {
                return (a.score || 0) - (b.score || 0);
            });
        }
        var cap = limit && limit > 0 ? limit : rows.length;
        return rows.length > cap ? rows.slice(0, cap) : rows;
    }
}
