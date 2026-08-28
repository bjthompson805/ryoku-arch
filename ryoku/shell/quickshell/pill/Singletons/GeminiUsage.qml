import QtQuick
import Quickshell
import Quickshell.Io

// Gemini / Antigravity usage source for the bar's agent-usage readout.
// Estimates session (5-hour) and weekly (7-day) token consumption, limits, and
// model breakdown by scanning local Antigravity CLI transcripts in ~/.gemini/antigravity-cli.
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
    readonly property bool refreshing: scanProc.running

    function refresh() {
        root._refreshUsage(false);
    }

    function refreshNow() {
        root._refreshUsage(true);
    }

    function refreshIfStale() {
        var now = Date.now();
        if (now - root.lastCheckedMs >= 120000)
            root._refreshUsage(false);
    }

    function _refreshUsage(force) {
        if (scanProc.running)
            return;
        var now = Date.now();
        var floor = force ? root.manualCooldownMs : root.minRetryIntervalMs;
        if (now - root.lastAttemptMs < floor)
            return;
        root.lastAttemptMs = now;
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

    function _recentDateStrings() {
        var out = [];
        var now = new Date();
        for (var i = 6; i >= 0; i--) {
            var d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
            out.push(d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"));
        }
        return out;
    }

    function _applyUsage(r) {
        root.lastCheckedMs = Date.now();
        if (!r || !r.hasData) {
            root.available = root.everHadLimits;
            root.lastProbeFailed = true;
            root.authHelpText = "Run `agy` to start Antigravity sessions.";
            return;
        }

        root.planLabel = r.planLabel || "Pro";
        root.sessionPercent = r.sessionPercent || 0;
        root.weeklyPercent = r.weeklyPercent || 0;
        root.sessionResetsAtMs = r.sessionResetsAtMs !== undefined ? r.sessionResetsAtMs : -1;
        root.weeklyResetsAtMs = r.weeklyResetsAtMs !== undefined ? r.weeklyResetsAtMs : -1;
        root.available = true;
        root.everHadLimits = true;
        root.lastProbeFailed = false;
        root.lastUpdatedMs = root.lastCheckedMs;

        var dates = root._recentDateStrings();
        var days = [];
        for (var i = 0; i < dates.length; i++)
            days.push({ date: dates[i], tokens: Number((r.byDay || {})[dates[i]] || 0) });
        root.recentDays = days;

        var models = [];
        for (var id in (r.byModel || {}))
            models.push({ id: id, name: root.friendlyModelName(id), total: Number(r.byModel[id] || 0) });
        models.sort(function(a, b) { return b.total - a.total; });
        root.modelUsage = models.slice(0, 4);

        root.localStatsAvailable = true;
        root.lastLocalStatsMs = root.lastCheckedMs;
        root._writeCache();
    }

    function _applyUsageError(message) {
        root.available = root.everHadLimits;
        root.lastProbeFailed = true;
        root.lastCheckedMs = Date.now();
        root.authHelpText = message || "Couldn't read Antigravity session data.";
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

    Process {
        id: scanProc
        command: ["bash", "-c",
            "dir=\"$0\"\n" +
            "plan=\"${GEMINI_PLAN:-${GOOGLE_AI_PLAN:-}}\"\n" +
            "if [ -z \"$plan\" ] && [ -f \"$dir/settings.json\" ]; then\n" +
            "  plan=$(jq -r '.plan // .tier // empty' \"$dir/settings.json\" 2>/dev/null)\n" +
            "fi\n" +
            "if [ -z \"$plan\" ] && [ -f \"$dir/cache/onboarding.json\" ]; then\n" +
            "  if [ \"$(jq -r '.enterpriseOnboardingComplete // false' \"$dir/cache/onboarding.json\" 2>/dev/null)\" = \"true\" ]; then\n" +
            "    plan=\"Enterprise\"\n" +
            "  fi\n" +
            "fi\n" +
            "now_s=$(date +%s)\n" +
            "five_h_ago_s=$((now_s - 18000))\n" +
            "seven_d_ago_s=$((now_s - 604800))\n" +
            "find \"$dir/brain\" -type f -name 'transcript*.jsonl' -mtime -8 -print0 2>/dev/null" +
            " | xargs -0 -r cat 2>/dev/null" +
            " | jq -c 'select(.created_at != null and (.type == \"PLANNER_RESPONSE\" or .type == \"USER_INPUT\" or .type == \"GENERIC\")) | {" +
            "     day: (.created_at[0:10])," +
            "     ts: (.created_at | fromdateiso8601? // 0)," +
            "     type: .type," +
            "     model: \"Gemini 3.7 Flash\"," +
            "     tokens: (((((.content // \"\") | length) + ((.thinking // \"\") | length)) / 3.8 | floor) + (if .type == \"PLANNER_RESPONSE\" then 500 else 0 end))" +
            "   }' 2>/dev/null" +
            " | jq -s --argjson now \"$now_s\" --argjson five_h \"$five_h_ago_s\" --argjson seven_d \"$seven_d_ago_s\" --arg plan \"$plan\" '" +
            "   (if length == 0 then [] else . end) as $rows |" +
            "   ($rows | map(select(.tokens > 0))) as $valid |" +
            "   ($valid | map(select(.ts >= $five_h))) as $s5h |" +
            "   ($valid | map(select(.ts >= $seven_d))) as $s7d |" +
            "   ($s5h | map(.tokens) | add // 0) as $sessionTokens |" +
            "   ($s7d | map(.tokens) | add // 0) as $weeklyTokens |" +
            "   ($s5h | map(.ts) | min // null) as $min5h |" +
            "   ($s7d | map(.ts) | min // null) as $min7d |" +
            "   (if ($plan | length) > 0 then $plan elif ($valid | any((.model // \"\") | test(\"ultra\"; \"i\"))) then \"Ultra\" else \"Pro\" end) as $resolvedPlan |" +
            "   (if $resolvedPlan == \"Ultra\" then {s: 2000000, w: 20000000}" +
            "    elif $resolvedPlan == \"Enterprise\" then {s: 5000000, w: 50000000}" +
            "    elif $resolvedPlan == \"Free\" then {s: 100000, w: 1000000}" +
            "    else {s: 500000, w: 5000000} end) as $cap |" +
            "   {" +
            "     byDay: ($valid | group_by(.day) | map({key: .[0].day, value: (map(.tokens) | add)}) | from_entries)," +
            "     byModel: ($valid | group_by(.model) | map({key: .[0].model, value: (map(.tokens) | add)}) | from_entries)," +
            "     sessionTokens: $sessionTokens," +
            "     weeklyTokens: $weeklyTokens," +
            "     sessionPercent: ([($sessionTokens / ($cap.s / 100)) | round, 100] | min)," +
            "     weeklyPercent: ([($weeklyTokens / ($cap.w / 100)) | round, 100] | min)," +
            "     sessionResetsAtMs: (if $min5h != null then (($min5h + 18000) * 1000) else -1 end)," +
            "     weeklyResetsAtMs: (if $min7d != null then (($min7d + 604800) * 1000) else -1 end)," +
            "     planLabel: $resolvedPlan," +
            "     hasData: ($valid | length > 0)" +
            "   }'",
            root.geminiHome
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var r = JSON.parse(this.text);
                    root._applyUsage(r);
                } catch (e) {
                    root._applyUsageError("Couldn't parse Antigravity session data.");
                }
            }
        }
    }

    Timer {
        interval: 120000
        repeat: true
        running: root.active
        onTriggered: root.refreshIfStale()
    }
}
