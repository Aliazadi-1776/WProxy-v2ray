import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/Commands.js" as Commands

Plasma5Support.DataSource {
    id: runner
    engine: "executable"
    connectedSources: []
    interval: 0

    property var jobs: ({})
    signal completed(string token, int exitCode, string output, string error)

    function run(token, args) {
        const source = Commands.command(args);
        if (jobs[source])
            return false;
        jobs[source] = {token: token, started: Date.now()};
        connectSource(source);
        return true;
    }

    onNewData: function(sourceName, data) {
        if (!jobs[sourceName] || data["exit code"] === undefined)
            return;
        const token = jobs[sourceName].token;
        delete jobs[sourceName];
        disconnectSource(sourceName);
        completed(token, Number(data["exit code"]), String(data.stdout || ""), String(data.stderr || ""));
    }

    property Timer watchdog: Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            for (const source in runner.jobs) {
                const job = runner.jobs[source];
                if (Date.now() - job.started < 120000)
                    continue;
                delete runner.jobs[source];
                runner.disconnectSource(source);
                runner.completed(job.token, 124, "", "Command timed out. Check WProxy and the Plasma5Support executable engine.");
            }
        }
    }

    Component.onDestruction: {
        for (const source in jobs)
            disconnectSource(source);
    }
}
