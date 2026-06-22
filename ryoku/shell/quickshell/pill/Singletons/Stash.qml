pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

/**
 * File stash bridge: a live snapshot of ~/Downloads/Stash and the back-end for
 * the stash surface. The FolderListModel watches the directory (created on first
 * load) so the grid stays current without polling; openFile, removeFile, clearAll
 * and addUrl drive it through detached coreutils.
 *
 * Three flows sit on top, all behind helper scripts under ~/.config/hypr/scripts:
 *  - LocalSend send. openSendPicker / openSendAll / openSendText kick a ~2s LAN
 *    discovery (lsState scanning|ready|sending); sendTo uploads the picked file,
 *    the whole stash, or a typed note (written to a temp file) to the chosen IP.
 *  - LocalSend receive. start/stopReceive run localsend.sh receive, a server that
 *    announces us on the LAN and drops incoming files into the stash; it streams
 *    READY/INCOMING/SAVED lines that drive recvState / recvAlias / recvCount.
 *  - Rail jobs. requestInstall/Compress/Download raise a confirm (taskState
 *    confirm); confirmTask runs the helper (running -> done|error). Download pulls
 *    its link from the clipboard so it needs no in-surface keyboard grab.
 */
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string dir: home + "/Downloads/Stash"
    readonly property string script: home + "/.config/hypr/scripts/localsend.sh"
    readonly property string scriptDir: home + "/.config/hypr/scripts"

    readonly property alias files: files
    readonly property int count: files.count
    readonly property alias deviceModel: deviceModel

    // Send flow.
    property string lsState: "idle"       // idle | scanning | ready | sending
    property string sendKind: "file"      // file | all | text
    property string pendingFile: ""
    property string composeText: ""

    // Receive flow.
    property string recvState: "idle"     // idle | listening
    property string recvAlias: ""
    property int recvCount: 0
    property string recvLast: ""

    // Rail jobs.
    property string task: ""              // "" | install | compress | download
    property string taskState: "idle"     // idle | confirm | running | done | error
    property string taskMsg: ""
    property string downloadUrl: ""

    function openFile(path) {
        Quickshell.execDetached(["xdg-open", path]);
    }

    function removeFile(path) {
        Quickshell.execDetached(["rm", "-f", path]);
    }

    function clearAll() {
        Quickshell.execDetached(["sh", "-c", "rm -f \"$1\"/*", "--", root.dir]);
    }

    function addUrl(url) {
        var p = ("" + url).replace(/^file:\/\//, "");
        Quickshell.execDetached(["cp", "-n", p, root.dir]);
    }

    // ── Send ────────────────────────────────────────────────────────────
    function startScan() {
        deviceModel.clear();
        root.lsState = "scanning";
        discoverProc.running = true;
    }

    function openSendPicker(file) {
        root.sendKind = "file";
        root.pendingFile = file;
        startScan();
    }

    function openSendAll() {
        if (root.count === 0)
            return;
        root.sendKind = "all";
        root.pendingFile = "";
        startScan();
    }

    function openSendText() {
        root.sendKind = "text";
        root.pendingFile = "";
        root.composeText = "";
        startScan();
    }

    function cancelSend() {
        discoverProc.running = false;
        root.lsState = "idle";
        root.pendingFile = "";
        root.composeText = "";
    }

    function pasteCompose() {
        pasteProc.running = true;
    }

    function sendTo(ip) {
        root.lsState = "sending";
        if (root.sendKind === "all")
            sendProc.command = ["bash", root.script, "send-all", root.dir, ip];
        else if (root.sendKind === "text")
            // Notes have no file: drop the text into a temp file named note.txt so
            // the receiver shows a sensible name, send it, then clean up.
            sendProc.command = ["bash", "-c",
                "d=$(mktemp -d) && printf '%s' \"$1\" > \"$d/note.txt\" && bash \"$2\" send \"$d/note.txt\" \"$3\"; r=$?; rm -rf \"$d\"; exit $r",
                "--", root.composeText, root.script, ip];
        else
            sendProc.command = ["bash", root.script, "send", root.pendingFile, ip];
        sendProc.running = true;
    }

    // ── Receive ─────────────────────────────────────────────────────────
    function startReceive() {
        root.recvCount = 0;
        root.recvLast = "";
        root.recvAlias = "Ryoku Stash";
        root.recvState = "listening";
        recvProc.running = true;
    }

    function stopReceive() {
        recvProc.running = false;
        root.recvState = "idle";
    }

    function onRecvLine(line) {
        var t = ("" + line).split("\t");
        if (t[0] === "READY") {
            root.recvAlias = t[1] || "Ryoku Stash";
            root.recvState = "listening";
        } else if (t[0] === "INCOMING") {
            root.recvLast = t[1] || "";
        } else if (t[0] === "SAVED") {
            root.recvCount += 1;
            root.recvLast = t[1] || "";
        } else if (t[0] === "ERROR") {
            root.recvState = "idle";
        }
    }

    // ── Rail jobs ───────────────────────────────────────────────────────
    function requestInstall() {
        if (root.count > 0) {
            root.task = "install";
            root.taskMsg = "";
            root.taskState = "confirm";
        }
    }

    function requestCompress() {
        if (root.count > 0) {
            root.task = "compress";
            root.taskMsg = "";
            root.taskState = "confirm";
        }
    }

    // The clipboard read settles the confirm: a link enables it, anything else
    // turns it straight into the "copy a link first" error.
    function requestDownload() {
        root.task = "download";
        root.taskMsg = "";
        root.downloadUrl = "";
        root.taskState = "confirm";
        clipProc.running = true;
    }

    function confirmTask() {
        if (root.task === "install")
            runTask("install", ["bash", root.scriptDir + "/stash-install.sh"]);
        else if (root.task === "compress")
            runTask("compress", ["bash", root.scriptDir + "/stash-compress.sh"]);
        else if (root.task === "download" && root.downloadUrl.length > 0)
            runTask("download", ["bash", root.scriptDir + "/stash-download.sh", root.downloadUrl]);
    }

    function runTask(name, cmd) {
        root.task = name;
        root.taskMsg = "";
        root.taskState = "running";
        taskProc.command = cmd;
        taskProc.running = true;
    }

    function dismissTask() {
        root.task = "";
        root.taskState = "idle";
        root.taskMsg = "";
        root.downloadUrl = "";
    }

    FolderListModel {
        id: files
        folder: "file://" + root.dir
        showDirs: false
        showHidden: false
        nameFilters: ["*"]
    }

    ListModel {
        id: deviceModel
    }

    Process {
        id: discoverProc
        command: ["bash", root.script, "discover"]
        stdout: StdioCollector {
            id: discoverOut
        }
        onExited: {
            if (root.lsState !== "scanning")
                return;
            deviceModel.clear();
            var ipRe = /^\d{1,3}(\.\d{1,3}){3}$/;
            var lines = discoverOut.text.split("\n");
            for (var i = 0; i < lines.length; i++) {
                var parts = lines[i].split("\t");
                if (parts.length === 2 && ipRe.test(parts[1].trim()))
                    deviceModel.append({ alias: parts[0].trim(), ip: parts[1].trim() });
            }
            root.lsState = "ready";
        }
    }

    Process {
        id: sendProc
        onExited: {
            root.lsState = "idle";
            root.pendingFile = "";
            root.composeText = "";
        }
    }

    Process {
        id: recvProc
        command: ["bash", root.script, "receive"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root.onRecvLine(line)
        }
        onExited: if (root.recvState !== "idle") root.recvState = "idle"
    }

    Process {
        id: taskProc
        stdout: StdioCollector { id: taskOut }
        onExited: (exitCode) => {
            var lines = ("" + taskOut.text).split("\n");
            var last = "";
            for (var i = 0; i < lines.length; i++) {
                if (lines[i].trim().length > 0)
                    last = lines[i].trim();
            }
            root.taskMsg = last;
            root.taskState = exitCode === 0 ? "done" : "error";
        }
    }

    Process {
        id: pasteProc
        command: ["wl-paste", "-n"]
        stdout: StdioCollector { id: pasteOut }
        onExited: root.composeText = ("" + pasteOut.text)
    }

    Process {
        id: clipProc
        command: ["wl-paste", "-n"]
        stdout: StdioCollector { id: clipOut }
        onExited: {
            var u = ("" + clipOut.text).trim();
            if (/^https?:\/\/\S+/.test(u))
                root.downloadUrl = u;
            else {
                root.taskState = "error";
                root.taskMsg = "Copy a link first, then tap download";
            }
        }
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.dir])
}
