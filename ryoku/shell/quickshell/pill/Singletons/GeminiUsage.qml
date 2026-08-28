import QtQuick
import Quickshell
import Quickshell.Io

// Gemini / Antigravity usage source for the bar's agent-usage readout.
// Probes the official Antigravity CLI `/usage` figures for exact server-side
// session (5-hour) and weekly (7-day) rate-limit percentages and reset countdowns,
// while scanning local transcripts for the token-by-day and token-by-model breakdown.
Item {
    id: root
    visible: false

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku"
    readonly property string geminiHome: Quickshell.env("GEMINI_CONFIG_DIR") || (Quickshell.env("HOME") + "/.gemini/antigravity-cli")

    property bool active: false
    property bool available: false
    property bool everHadLimits: false
    property bool lastProbeFailed: false
    property real lastCheckedMs: 0
    property real lastUpdatedMs: 0
    property string planLabel: "Pro"
    readonly property string sessionLabel: "Session (5-hour)"
    readonly property string weeklyLabel: "Weekly (7-day)"
    property int sessionPercent: 0
    property int weeklyPercent: 0
    property real sessionResetsAtMs: -1
    property real weeklyResetsAtMs: -1
    property string authHelpText: "Run `agy` to start Antigravity sessions."

    property bool localStatsAvailable: false
    property var recentDays: []
    property var modelUsage: []

    readonly property int minRetryIntervalMs: 15000
    readonly property int manualCooldownMs: 5000
    property real lastAttemptMs: 0
    property real lastLocalStatsMs: 0
    readonly property bool refreshing: probeProc.running || scanProc.running

    function refresh() {
        root._refreshLimits(false);
        root._refreshLocalStats();
    }

    function refreshNow() {
        root._refreshLimits(true);
        root._refreshLocalStats();
    }

    function refreshIfStale() {
        var now = Date.now();
        if (now - root.lastCheckedMs >= 120000)
            root._refreshLimits(false);
        if (now - root.lastLocalStatsMs >= 900000)
            root._refreshLocalStats();
    }

    function _refreshLimits(force) {
        if (probeProc.running)
            return;
        var now = Date.now();
        var floor = force ? root.manualCooldownMs : root.minRetryIntervalMs;
        if (now - root.lastAttemptMs < floor)
            return;
        root.lastAttemptMs = now;
        probeProc.running = true;
    }

    function _refreshLocalStats() {
        if (!scanProc.running)
            scanProc.running = true;
    }

    function formatTokenCount(n) {
        var v = Number(n) || 0;
        if (v >= 1e9) return (v / 1e9).toFixed(1) + "B";
        if (v >= 1e6) return (v / 1e6).toFixed(1) + "M";
        if (v >= 1e3) return (v / 1e3).toFixed(1) + "K";
        return String(Math.round(v));
    }

    function friendlyModelName(id) {
        if (!id || id.length === 0)
            return "Gemini 3.7 Flash";
        return String(id);
    }

    function _applyLimits(r) {
        root.lastCheckedMs = Date.now();
        root.planLabel = r.planLabel || "Pro";
        root.sessionPercent = r.sessionPercent || 0;
        root.weeklyPercent = r.weeklyPercent || 0;
        root.sessionResetsAtMs = r.sessionResetsAtMs !== undefined ? r.sessionResetsAtMs : -1;
        root.weeklyResetsAtMs = r.weeklyResetsAtMs !== undefined ? r.weeklyResetsAtMs : -1;
        root.available = true;
        root.everHadLimits = true;
        root.lastProbeFailed = false;
        root.lastUpdatedMs = root.lastCheckedMs;
        root._writeCache();
    }

    function _applyLimitsError(message) {
        root.available = root.everHadLimits;
        root.lastProbeFailed = true;
        root.lastCheckedMs = Date.now();
        root.authHelpText = message || "Couldn't reach Antigravity usage endpoint.";
    }

    function _recentDateStrings() {
        var out = [];
        var now = new Date();
        for (var i = 6; i >= 0; i--) {
            var d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
            out.push(d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"));
        }
        return out;
    }

    function _applyLocalStats(byDay, byModel) {
        var dates = root._recentDateStrings();
        var days = [];
        for (var i = 0; i < dates.length; i++)
            days.push({ date: dates[i], tokens: Number((byDay || {})[dates[i]] || 0) });
        root.recentDays = days;

        var models = [];
        for (var id in (byModel || {}))
            models.push({ id: id, name: root.friendlyModelName(id), total: Number(byModel[id] || 0) });
        models.sort(function(a, b) { return b.total - a.total; });
        root.modelUsage = models.slice(0, 4);

        root.localStatsAvailable = true;
        root.lastLocalStatsMs = Date.now();
        root._writeCache();
    }

    function _writeCache() {
        cacheFile.setText(JSON.stringify({
            planLabel: root.planLabel,
            sessionPercent: root.sessionPercent,
            weeklyPercent: root.weeklyPercent,
            sessionResetsAtMs: root.sessionResetsAtMs,
            weeklyResetsAtMs: root.weeklyResetsAtMs,
            lastUpdatedMs: root.lastUpdatedMs,
            recentDays: root.recentDays,
            modelUsage: root.modelUsage
        }));
    }

    function _loadCache() {
        try {
            var c = JSON.parse(cacheFile.text());
            root.planLabel = c.planLabel || "Pro";
            root.sessionPercent = c.sessionPercent || 0;
            root.weeklyPercent = c.weeklyPercent || 0;
            root.sessionResetsAtMs = c.sessionResetsAtMs === undefined ? -1 : c.sessionResetsAtMs;
            root.weeklyResetsAtMs = c.weeklyResetsAtMs === undefined ? -1 : c.weeklyResetsAtMs;
            root.lastUpdatedMs = c.lastUpdatedMs || 0;
            if (c.sessionPercent !== undefined || c.weeklyPercent !== undefined) {
                root.available = true;
                root.everHadLimits = true;
            }
            if (Array.isArray(c.recentDays) && c.recentDays.length > 0) {
                root.recentDays = c.recentDays;
                root.localStatsAvailable = true;
            }
            if (Array.isArray(c.modelUsage))
                root.modelUsage = c.modelUsage;
        } catch (e) {}
    }

    Component.onCompleted: root._loadCache()

    Process {
        command: ["mkdir", "-p", root.stateDir]
        running: true
    }

    FileView {
        id: cacheFile
        path: root.stateDir + "/agent-usage-gemini.json"
        blockLoading: true
        printErrors: false
    }

    // Rate-limit probe: reads official server quotas via `agy --print "/usage"`
    Process {
        id: probeProc
        command: ["bash", "-c",
            "dir=\"$0\"\n" +
            "plan=\"${GEMINI_PLAN:-${GOOGLE_AI_PLAN:-}}\"\n" +
            "if [ -z \"$plan\" ] && [ -f \"$dir/settings.json\" ]; then\n" +
            "    plan=$(jq -r '.plan // .tier // empty' \"$dir/settings.json\" 2>/dev/null)\n" +
            "fi\n" +
            "if [ -z \"$plan\" ] && [ -f \"$dir/cache/onboarding.json\" ]; then\n" +
            "    if [ \"$(jq -r '.enterpriseOnboardingComplete // false' \"$dir/cache/onboarding.json\" 2>/dev/null)\" = \"true\" ]; then\n" +
            "        plan=\"Enterprise\"\n" +
            "    fi\n" +
            "fi\n" +
            "if [ -z \"$plan\" ]; then\n" +
            "    plan=\"Pro\"\n" +
            "fi\n" +
            "output=$(agy --print \"/usage\" 2>/dev/null)\n" +
            "if [ -z \"$output\" ]; then\n" +
            "    echo '{\"success\": false}'\n" +
            "    exit 0\n" +
            "fi\n" +
            "echo \"$output\" | python3 -c '\n" +
            "import sys, re, json\n" +
            "text = sys.stdin.read()\n" +
            "res = {\"success\": False, \"planLabel\": sys.argv[1], \"sessionPercent\": 0, \"weeklyPercent\": 0, \"sessionResetsAtMs\": -1, \"weeklyResetsAtMs\": -1}\n" +
            "for line in text.splitlines():\n" +
            "    m = re.search(r\"Gemini Models\\s+(Weekly Limit Remaining|Five Hour Limit Remaining)\\s+(\\d+)%\\s+(\\S+)\", line)\n" +
            "    if m:\n" +
            "        res[\"success\"] = True\n" +
            "        limit_type, remaining_pct, reset_time = m.groups()\n" +
            "        used_pct = max(0, min(100, 100 - int(remaining_pct)))\n" +
            "        try:\n" +
            "            from datetime import datetime\n" +
            "            reset_ts = int(datetime.fromisoformat(reset_time.replace(\"Z\", \"+00:00\")).timestamp() * 1000)\n" +
            "        except Exception: reset_ts = -1\n" +
            "        if \"Five Hour\" in limit_type:\n" +
            "            res[\"sessionPercent\"] = used_pct\n" +
            "            res[\"sessionResetsAtMs\"] = reset_ts\n" +
            "        elif \"Weekly\" in limit_type:\n" +
            "            res[\"weeklyPercent\"] = used_pct\n" +
            "            res[\"weeklyResetsAtMs\"] = reset_ts\n" +
            "print(json.dumps(res))\n" +
            "' \"$plan\"",
            root.geminiHome
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var r = JSON.parse(this.text);
                    if (r && r.success) {
                        root._applyLimits(r);
                    } else {
                        root._applyLimitsError("Run `agy` to see usage.");
                    }
                } catch (e) {
                    root._applyLimitsError("Couldn't parse Antigravity limits.");
                }
            }
        }
    }

    // Local transcript scan: tokens by day & tokens by model
    Process {
        id: scanProc
        command: ["bash", "-c",
            "find \"$0/brain\" -type f -name 'transcript*.jsonl' -mtime -8 -print0 2>/dev/null" +
            " | xargs -0 -r cat 2>/dev/null" +
            " | jq -c 'select(.created_at != null and (.type == \"PLANNER_RESPONSE\" or .type == \"USER_INPUT\" or .type == \"GENERIC\")) | {" +
            "     day: (.created_at[0:10])," +
            "     type: .type," +
            "     model: \"Gemini 3.7 Flash\"," +
            "     tokens: (((((.content // \"\") | length) + ((.thinking // \"\") | length)) / 3.8 | floor) + (if .type == \"PLANNER_RESPONSE\" then 500 else 0 end))" +
            "   }' 2>/dev/null" +
            " | jq -s '" +
            "   (if length == 0 then [] else . end) as $rows |" +
            "   ($rows | map(select(.tokens > 0))) as $valid |" +
            "   {" +
            "     byDay: ($valid | group_by(.day) | map({key: .[0].day, value: (map(.tokens) | add)}) | from_entries)," +
            "     byModel: ($valid | group_by(.model) | map({key: .[0].model, value: (map(.tokens) | add)}) | from_entries)" +
            "   }'",
            root.geminiHome
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var r = JSON.parse(this.text);
                    root._applyLocalStats(r.byDay, r.byModel);
                } catch (e) {}
            }
        }
    }

    // Rate-limit probe polls every 2 minutes
    Timer {
        interval: 120000
        repeat: true
        running: root.active
        onTriggered: root.refreshIfStale()
    }

    // Local transcript scan polls every 15 minutes
    Timer {
        interval: 900000
        repeat: true
        running: root.active
        onTriggered: root.refreshIfStale()
    }
}
