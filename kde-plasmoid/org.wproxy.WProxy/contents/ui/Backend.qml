import QtQuick
import "../code/Commands.js" as Commands

Item {
    id: backend
    visible: false
    property string cliPath: "/usr/bin/wproxyctl"
    property string managerPath: "/usr/bin/wproxy-manager"
    property string pkexecPath: "/usr/bin/pkexec"
    property bool pollingEnabled: true
    property bool busy: false
    property bool active: false
    property string activeId: ""
    property string activeName: ""
    property string connectingId: ""
    property string selectedId: ""
    property string errorMessage: ""
    property string traffic: ""
    property var nodes: []
    property var latencies: ({})
    property var pinging: ({})
    property string nodeSignature: ""
    property bool syncRetried: false
    property var executor: commands
    signal subscriptionAdded()

    function run(token, args) {
        return executor.run(token, [cliPath].concat(args));
    }

    function refresh() {
        if (busy)
            return;
        run("status", ["status", "--json"]);
        run("nodes", ["node", "list", "--json"]);
        run("subs", ["sub", "list", "--json"]);
    }

    function finish(error) {
        busy = false;
        connectingId = "";
        errorMessage = error || "";
        refresh();
    }

    function connectNode(id) {
        if (busy || !id)
            return;
        busy = true;
        errorMessage = "";
        connectingId = id;
        selectedId = id;
        syncRetried = false;
        run("connect", ["nm", "up", id]);
    }

    function toggleConnection() {
        if (active)
            disconnect();
        else if (nodes.length)
            connectNode(selectedId || nodes[0].id);
    }

    function disconnect() {
        if (busy)
            return;
        busy = true;
        run("disconnect", ["nm", "down"]);
    }

    function sync(token) {
        executor.run(token, [pkexecPath, cliPath, "nm", "sync"]);
    }

    function addSubscription(url) {
        url = url.trim();
        if (busy)
            return;
        if (!/^https?:\/\/\S+$/i.test(url)) {
            errorMessage = qsTr("Enter an http(s) subscription URL.");
            return;
        }
        busy = true;
        errorMessage = "";
        run("sub-add", ["sub", "add", url]);
    }

    function updateSubscriptions() {
        if (busy)
            return;
        busy = true;
        errorMessage = "";
        run("sub-update", ["sub", "update"]);
    }

    function pingNode(id) {
        if (pinging[id] || busy)
            return;
        const next = Object.assign({}, pinging);
        next[id] = true;
        pinging = next;
        run("ping:" + id, ["node", "ping", id, "--json", "--timeout", "2.0"]);
    }

    function pingAll() {
        if (busy || Object.keys(pinging).length || !nodes.length)
            return;
        const next = {};
        nodes.forEach(function(node) { next[node.id] = true; });
        pinging = next;
        run("ping-all", ["node", "ping", "--all", "--json", "--timeout", "2.0"]);
    }

    function openManager() {
        executor.run("manager", [managerPath]);
    }

    function consume(token, code, output, error) {
        const failure = error.trim() || output.trim() || qsTr("Command failed (%1)").arg(code);
        if (token === "connect") {
            if (code && !syncRetried && Commands.needsSync(failure)) {
                syncRetried = true;
                sync("connect-sync");
            } else {
                finish(code ? failure : "");
            }
            return;
        }
        if (token === "connect-sync") {
            if (code)
                finish(failure);
            else
                run("connect", ["nm", "up", connectingId]);
            return;
        }
        if (token === "disconnect" || token === "sub-sync") {
            finish(code ? failure : "");
            return;
        }
        if (token === "sub-add") {
            if (code || !output.trim()) {
                finish(failure);
            } else {
                subscriptionAdded();
                run("sub-update", ["sub", "update", output.trim()]);
            }
            return;
        }
        if (token === "sub-update") {
            if (code)
                finish(failure);
            else
                sync("sub-sync");
            return;
        }
        if (token === "manager") {
            if (code)
                errorMessage = failure;
            return;
        }
        const isPing = token === "ping-all" || token.indexOf("ping:") === 0;
        if (isPing) {
            const next = Object.assign({}, pinging);
            if (token === "ping-all") {
                pinging = {};
            } else {
                delete next[token.slice(5)];
                pinging = next;
            }
        }
        if (code) {
            errorMessage = failure;
            return;
        }
        let data;
        try {
            data = JSON.parse(output);
        } catch (e) {
            errorMessage = qsTr("Invalid WProxy response: %1").arg(String(e));
            return;
        }
        if (token === "status") {
            active = Boolean(data.active);
            activeId = data.node_id || "";
            activeName = (data.name || "").replace(/^WProxy · /, "");
            if (activeId)
                selectedId = activeId;
        } else if (token === "nodes" && Array.isArray(data)) {
            const signature = Commands.signature(data);
            if (signature !== nodeSignature) {
                nodeSignature = signature;
                nodes = data;
            }
        } else if (token === "subs" && Array.isArray(data)) {
            const sub = data.find(function(item) { return item.remaining_human; });
            traffic = sub ? sub.remaining_human : "";
        } else if (isPing && Array.isArray(data)) {
            const next = Object.assign({}, latencies);
            data.forEach(function(row) { next[row.id] = row.latency_ms; });
            latencies = next;
        }
    }

    CommandRunner {
        id: commands
    }
    Connections {
        target: backend.executor
        function onCompleted(token, exitCode, output, error) {
            backend.consume(token, exitCode, output, error);
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: backend.pollingEnabled
        onTriggered: backend.refresh()
    }
    Component.onCompleted: if (pollingEnabled) refresh()
}
