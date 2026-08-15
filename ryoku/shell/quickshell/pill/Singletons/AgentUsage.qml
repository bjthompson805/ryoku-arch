pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Claude Code's rate-limit usage for the bar's agent-usage readout. reads the
// OAuth access token Claude Code's CLI already keeps in
// ~/.claude/.credentials.json (claudeAiOauth.accessToken -- nothing else in
// that file is touched beyond the plan label, and the token goes nowhere but
// this one request's Authorization header) and probes Anthropic's own usage
// endpoint for the session (5-hour) and weekly (7-day) rate-limit percentages
// -- the same figures `claude usage` reports, no local transcript scanning
// for those two numbers. Separately, a local scan of ~/.claude/projects'
// *.jsonl transcripts (last 8 days only, to keep it bounded) builds the
// token-by-day and token-by-model breakdown the popout shows underneath the
// limits, mirroring Omarchy's agent-usage panel. last-good reading of both
// is cached to disk so a shell restart shows real numbers instead of blank
// ones until the next poll lands. the poller runs only while `active` (a
// visible BarAgentUsage sets it), same idiom as SysStats/NetSpeed.
Singleton {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku"
    readonly property string credentialsPath: (Quickshell.env("CLAUDE_CONFIG_DIR") || (Quickshell.env("HOME") + "/.claude")) + "/.credentials.json"
    readonly property string projectsPath: (Quickshell.env("CLAUDE_CONFIG_DIR") || (Quickshell.env("HOME") + "/.claude")) + "/projects"

    property bool active: false

    // ---- rate limits (Anthropic's usage endpoint) --------------------------
    property bool available: false
    property string planLabel: ""
    property int sessionPercent: 0
    property int weeklyPercent: 0
    // epoch ms, or -1 when unknown; kept raw (not pre-formatted) so the
    // popout's own countdown stays live while it's open instead of freezing
    // the text at fetch time.
    property real sessionResetsAtMs: -1
    property real weeklyResetsAtMs: -1
    property string authHelpText: "Run `claude auth login` to see usage."

    // ---- local transcript scan (token-by-day / token-by-model) -------------
    property bool localStatsAvailable: false
    // [{date: "YYYY-MM-DD", tokens: N}, ...] oldest -> newest, always 7 entries.
    property var recentDays: []
    // [{id, name, total}, ...] sorted desc, top 4.
    property var modelUsage: []

    // a 429 or transport failure shouldn't retry faster than this even if the
    // caller pokes refresh() again right away (mirrors Omarchy's collector).
    readonly property int minRetryIntervalMs: 15000
    property real lastAttemptMs: 0

    function refresh() {
        root._refreshLimits();
        root._refreshLocalStats();
    }

    function _refreshLimits() {
        if (probeProc.running)
            return;
        var now = Date.now();
        if (now - root.lastAttemptMs < root.minRetryIntervalMs)
            return;
        root.lastAttemptMs = now;
        tokenFile.reload();
    }

    function _refreshLocalStats() {
        if (!scanProc.running)
            scanProc.running = true;
    }

    // ---- formatting, shared with the popout --------------------------------

    function formatTokenCount(n) {
        var v = Number(n) || 0;
        if (v >= 1e9) return (v / 1e9).toFixed(1) + "B";
        if (v >= 1e6) return (v / 1e6).toFixed(1) + "M";
        if (v >= 1e3) return (v / 1e3).toFixed(1) + "K";
        return String(Math.round(v));
    }

    function _modelWordCase(word) {
        return word.charAt(0).toUpperCase() + word.slice(1);
    }

    // model ids arrive like "claude-opus-4-5" or "claude-haiku-4-5-20251001";
    // strip the "claude-" prefix and a trailing 8-digit date snapshot, rejoin
    // the numeric run into one version, title-case the rest.
    function friendlyModelName(id) {
        if (!id)
            return "Unknown";
        var name = String(id).replace(/^claude-/, "").replace(/-\d{8}$/, "");
        var parts = name.split("-");
        var words = [];
        var version = [];
        for (var i = 0; i < parts.length; i++) {
            var part = parts[i];
            if (part === "")
                continue;
            if (/^\d/.test(part)) {
                version.push(part);
                continue;
            }
            if (version.length > 0) {
                words.push(version.join("."));
                version = [];
            }
            words.push(root._modelWordCase(part));
        }
        if (version.length > 0)
            words.push(version.join("."));
        return words.length > 0 ? words.join(" ") : "Unknown";
    }

    // ---- rate-limit parsing --------------------------------------------

    // Anthropic's usage endpoint reports percentages (37.0) on some payloads
    // and fractions (0.37) on others. A single value can't tell which -- a
    // genuine 0.5% usage and a 0.5 fraction (50%) look identical -- so the
    // scale is settled once per payload from whichever field is unambiguous
    // (any raw value >= 1 means the payload speaks percent), same as
    // Omarchy's collector.
    function _percentScale(rawValues) {
        for (var i = 0; i < rawValues.length; i++) {
            var n = Number(rawValues[i]);
            if (n >= 1)
                return true;
        }
        return false;
    }

    function _normalizePercent(raw, percentScale) {
        var n = Number(raw);
        if (!(n >= 0))
            return -1;
        return Math.round(Math.min(100, percentScale ? n : n * 100));
    }

    function _resetMs(raw) {
        if (raw === undefined || raw === null || raw === "")
            return -1;
        var n = Number(raw);
        var d = !isNaN(n) && /^[0-9.]+$/.test(String(raw).trim())
            ? new Date(n < 1e12 ? n * 1000 : n)
            : new Date(raw);
        var ms = d.getTime();
        return isNaN(ms) ? -1 : ms;
    }

    function _planLabel(tier, subscription) {
        var t = String(tier || "");
        var m = /max_(\d+x)/i.exec(t);
        if (m)
            return "Max " + m[1].toUpperCase();
        var s = String(subscription || "");
        return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : "";
    }

    function _applyLimits(payload) {
        var session = payload.five_hour;
        var weekly = payload.seven_day_oauth_apps || payload.seven_day;
        var percentScale = root._percentScale([
            session ? session.utilization : undefined,
            weekly ? weekly.utilization : undefined
        ]);
        var sp = session ? root._normalizePercent(session.utilization, percentScale) : -1;
        var wp = weekly ? root._normalizePercent(weekly.utilization, percentScale) : -1;
        if (sp < 0 && wp < 0) {
            root.available = false;
            root.authHelpText = "Anthropic's usage endpoint returned no limits.";
            return;
        }
        if (sp >= 0) {
            root.sessionPercent = sp;
            root.sessionResetsAtMs = root._resetMs(session.resets_at);
        }
        if (wp >= 0) {
            root.weeklyPercent = wp;
            root.weeklyResetsAtMs = root._resetMs(weekly.resets_at);
        }
        root.available = true;
        root._writeCache();
    }

    // ---- local-stats parsing --------------------------------------------

    // last 7 calendar days ending today, pre-seeded to 0 so a quiet day shows
    // as an empty bar instead of vanishing from the strip.
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
        models.sort(function (a, b) { return b.total - a.total; });
        root.modelUsage = models.slice(0, 4);

        root.localStatsAvailable = true;
        root._writeCache();
    }

    // ---- cache: last-good reading survives a restart -----------------------

    function _writeCache() {
        cacheFile.setText(JSON.stringify({
            planLabel: root.planLabel,
            sessionPercent: root.sessionPercent,
            weeklyPercent: root.weeklyPercent,
            sessionResetsAtMs: root.sessionResetsAtMs,
            weeklyResetsAtMs: root.weeklyResetsAtMs,
            recentDays: root.recentDays,
            modelUsage: root.modelUsage
        }));
    }

    function _loadCache() {
        var text = cacheFile.text();
        if (!text || text.length === 0)
            return;
        try {
            var c = JSON.parse(text);
            root.planLabel = c.planLabel || "";
            root.sessionPercent = c.sessionPercent || 0;
            root.weeklyPercent = c.weeklyPercent || 0;
            root.sessionResetsAtMs = c.sessionResetsAtMs === undefined ? -1 : c.sessionResetsAtMs;
            root.weeklyResetsAtMs = c.weeklyResetsAtMs === undefined ? -1 : c.weeklyResetsAtMs;
            if (c.sessionPercent !== undefined || c.weeklyPercent !== undefined)
                root.available = true;
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
        path: root.stateDir + "/agent-usage-claude.json"
        blockLoading: true
        printErrors: false
    }

    // read fresh (not watched -- the credentials file only needs checking
    // right before a probe) so a token rotated by `claude auth login` is
    // picked up on the very next poll instead of waiting on a stale watch.
    FileView {
        id: tokenFile
        path: root.credentialsPath
        blockLoading: true
        printErrors: false
        onLoaded: {
            var token = "";
            try {
                var data = JSON.parse(tokenFile.text());
                var login = data.claudeAiOauth || {};
                token = login.accessToken || "";
                root.planLabel = root._planLabel(login.rateLimitTier, login.subscriptionType);
            } catch (e) {}
            if (token.length === 0) {
                root.available = false;
                root.authHelpText = "Run `claude auth login` to see usage.";
                return;
            }
            probeProc.token = token;
            probeProc.running = true;
        }
        onLoadFailed: {
            root.available = false;
            root.authHelpText = "Run `claude auth login` to see usage.";
        }
    }

    Process {
        id: probeProc
        property string token: ""
        command: ["curl", "-s", "--max-time", "8",
            "-H", "Authorization: Bearer " + probeProc.token,
            "-H", "anthropic-beta: oauth-2025-04-20",
            "-H", "Accept: application/json",
            "https://api.anthropic.com/api/oauth/usage"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._applyLimits(JSON.parse(this.text));
                } catch (e) {
                    root.available = root.sessionPercent > 0 || root.weeklyPercent > 0;
                    root.authHelpText = "Couldn't reach Anthropic's usage endpoint.";
                }
            }
        }
    }

    // last 8 days of transcripts (by file mtime -- generous over the 7-day
    // display window so a session that started just before midnight isn't
    // lost), deduped by message id and summed per day / per model. jq is
    // already a dependency elsewhere in this shell (ryoku-plugins-place).
    // ~80MB / 70 files runs in a little over a second on a heavy transcript
    // history, so this rides the same poll cadence as the limits probe
    // rather than needing its own faster or slower timer.
    Process {
        id: scanProc
        // the projects path travels as $0 (bash's "$0" inside -c script is
        // the arg right after the script string), not string-interpolated
        // into the script itself, so it needs no shell-quoting of its own.
        command: ["bash", "-c",
            "find \"$0\" -name '*.jsonl' -mtime -8 -print0 2>/dev/null" +
            " | xargs -0 -r cat 2>/dev/null" +
            " | jq -c 'select((.type==\"assistant\") or (.message.role==\"assistant\"))" +
            " | (.message.usage // .usage) as $u | select($u != null)" +
            " | { id: (.message.id // .uuid // .requestId // \"\")," +
            "     day: ((.timestamp // .message.timestamp // \"\")[0:10])," +
            "     model: (.message.model // .model // \"claude\")," +
            "     tokens: (($u.input_tokens // $u.inputTokens // 0)" +
            "            + ($u.output_tokens // $u.outputTokens // 0)" +
            "            + ($u.cache_read_input_tokens // $u.cacheReadInputTokens // 0)" +
            "            + ($u.cache_creation_input_tokens // $u.cacheCreationInputTokens // 0)) }" +
            " | select(.tokens > 0 and .day != \"\")' 2>/dev/null" +
            " | jq -s '(if length == 0 then [] else unique_by(.id) end) as $rows" +
            " | { byDay: ($rows | group_by(.day) | map({key: .[0].day, value: (map(.tokens)|add)}) | from_entries)," +
            "     byModel: ($rows | group_by(.model) | map({key: .[0].model, value: (map(.tokens)|add)}) | from_entries) }'",
            root.projectsPath
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

    Timer {
        interval: 900000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
